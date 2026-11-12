# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_execution"

RSpec.describe SolidusMcp::Tools::AdjustStock do
  include_context "tool execution"

  let(:location) { Spree::StockLocation.create!(name: "Warehouse") }
  let(:variant) { product.master }
  let(:item) { location.stock_items.find_by!(variant_id: variant.id) }
  let(:arguments) do
    {variant_id: variant.id, stock_location_id: location.id, quantity: 5,
     reason: "Cycle count correction", idempotency_key: "count-1"}
  end

  def adjust(**overrides)
    execute("adjust_stock", **arguments.merge(overrides))
  end

  def restrict(&block)
    allow(Spree::Ability).to receive(:new).and_call_original
    ability = Spree::Ability.new(user)
    block.call(ability)
    allow(Spree::Ability).to receive(:new).with(user).and_return(ability)
  end

  it "creates a standard Solidus movement with a durable reason and result" do
    expect(adjust).to eq(stock_movement_id: Spree::StockMovement.last.id, stock_item_id: item.id,
      variant_id: variant.id, stock_location_id: location.id, quantity: 5,
      count_on_hand_before: 0, count_on_hand_after: 5)
    expect(item.reload.count_on_hand).to eq(5)
    movement = Spree::StockMovement.last
    expect(movement).to have_attributes(stock_item_id: item.id, quantity: 5)
    expect(movement.originator).to have_attributes(connection_policy_id: @saved.id,
      variant_id: variant.id, stock_location_id: location.id, reason: arguments[:reason], quantity: 5)
    expect(movement.originator.stock_movement).to eq(movement)
  end

  it "supports negative adjustments through the same workflow" do
    adjust
    result = adjust(quantity: -2, idempotency_key: "count-2")
    expect(result).to include(quantity: -2, count_on_hand_before: 5, count_on_hand_after: 3)
    expect(item.reload.count_on_hand).to eq(3)
  end

  it "returns the original result on retries even after other stock changes" do
    first = adjust
    adjust(quantity: 2, idempotency_key: "count-2")
    expect { expect(adjust).to eq(first) }.not_to change(Spree::StockMovement, :count)
    expect(SolidusMcp::StockAdjustment.count).to eq(2)
    expect(item.reload.count_on_hand).to eq(7)
  end

  it "retains retry protection when a token is replaced for the same connection" do
    first = adjust
    refreshed = create_token(application: application, user: user)
    expect(described_class.execute(credential: SolidusMcp::Credential.new(refreshed, user), **arguments)).to eq(first)
    expect(item.reload.count_on_hand).to eq(5)
  end

  it "rejects reuse with different quantity, reason, variant, or location" do
    first = adjust
    [{quantity: 2}, {reason: "Different"}, {variant_id: variant.id + 1}, {stock_location_id: location.id + 1}].each do |changes|
      expect { adjust(**changes) }.to raise_error(SolidusMcp::ToolError, /different inputs/)
    end
    expect(adjust).to eq(first)
    expect(item.reload.count_on_hand).to eq(5)
  end

  it "scopes request keys to a connection" do
    adjust
    other_app = create_application
    grant(application: other_app, user: user, permissions: ["adjust_stock"])
    other_token = create_token(application: other_app, user: user)
    described_class.execute(credential: SolidusMcp::Credential.new(other_token, user), **arguments)
    expect(item.reload.count_on_hand).to eq(10)
    expect(SolidusMcp::StockAdjustment.count).to eq(2)
  end

  it "isolates keys between users of the same OAuth application" do
    adjust
    other_user = create_user
    grant(application: application, user: other_user, permissions: ["adjust_stock"])
    other_token = create_token(application: application, user: other_user)
    described_class.execute(credential: SolidusMcp::Credential.new(other_token, other_user), **arguments)
    expect(item.reload.count_on_hand).to eq(10)
    expect(SolidusMcp::StockAdjustment.count).to eq(2)
  end

  it "rejects stock count overflow without consuming the request key" do
    adjust(quantity: 2147483647, idempotency_key: "maximum")
    expect { adjust(quantity: 1) }.to raise_error(SolidusMcp::ToolError, /integer range/)
    expect(item.reload.count_on_hand).to eq(2147483647)
    expect(Spree::StockMovement.count).to eq(1)
    expect(SolidusMcp::StockAdjustment.count).to eq(1)
  end

  it "rejects a negative balance when the stock item is not backorderable and allows retry after correction" do
    expect { adjust(quantity: -2) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(item.reload.count_on_hand).to eq(0)
    expect(Spree::StockMovement.count).to eq(0)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
    adjust(quantity: 3, idempotency_key: "restock")
    expect(adjust(quantity: -2)).to include(count_on_hand_after: 1)
  end

  it "permits negative balances on backorderable stock items" do
    item.update!(backorderable: true)
    expect(adjust(quantity: -2)).to include(count_on_hand_after: -2)
    expect(item.reload.count_on_hand).to eq(-2)
  end

  it "fills backorders through Solidus and does not fill them again on retry" do
    item.update!(backorderable: true)
    store = Spree::Store.create!(name: "Test", url: "example.test", code: "test", mail_from_address: "store@example.test")
    order = Spree::Order.create!(store: store, currency: "USD")
    line_item = Spree::LineItem.create!(order: order, variant: variant, quantity: 1, price: "12.50")
    shipment = Spree::Shipment.create!(order: order, stock_location: location)
    unit = Spree::InventoryUnit.create!(shipment: shipment, line_item: line_item, variant: variant, state: "backordered")
    order.update_column(:completed_at, Time.current)
    result = adjust(quantity: 1)
    expect(unit.reload.state).to eq("on_hand")
    expect(adjust(quantity: 1)).to eq(result)
    expect(Spree::StockMovement.where(stock_item: item).count).to eq(1)
  end

  it "rolls back movement and count when recording the result fails" do
    item
    allow_any_instance_of(SolidusMcp::StockAdjustment).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
    expect { adjust }.to raise_error(ActiveRecord::RecordInvalid)
    expect(item.reload.count_on_hand).to eq(0)
    expect(Spree::StockMovement.count).to eq(0)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
  end

  it "preserves movement validations" do
    item
    allow_any_instance_of(Spree::StockMovement).to receive(:valid?).and_return(false)
    expect { adjust }.to raise_error(ActiveRecord::RecordInvalid)
    expect(item.reload.count_on_hand).to eq(0)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
  end

  it "rejects invalid schemas and blank reasons" do
    [{quantity: 0}, {quantity: 1.5}, {quantity: "2"}, {quantity: 2147483648},
      {variant_id: 0}, {stock_location_id: 0}, {reason: ""}, {reason: "x" * 1001},
      {idempotency_key: ""}, {idempotency_key: "x" * 129}, {idempotency_key: "invalid key"}, {unknown: true}].each do |changes|
      expect { adjust(**changes) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
    arguments.each_key do |key|
      expect { execute("adjust_stock", **arguments.except(key)) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
    expect { adjust(reason: " \n ") }.to raise_error(SolidusMcp::ToolError, /blank/)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
  end

  it "requires its dedicated grant and OAuth write scope" do
    @saved.update!(permissions: ["get_inventory_levels", "update_variant"])
    expect { adjust }.to raise_error(SolidusMcp::AccessDenied)
    @saved.update!(permissions: ["adjust_stock"])
    token.update!(scopes: "mcp:read")
    expect { adjust }.to raise_error(SolidusMcp::InsufficientScope)
    token.update!(scopes: "mcp:write")
    expect(adjust).to include(count_on_hand_after: 5)
  end

  it "rejects missing stock items instead of creating one" do
    item.destroy!
    expect { adjust }.to raise_error(ActiveRecord::RecordNotFound)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
    expect(location.stock_items.where(variant_id: variant.id)).to be_empty
  end

  it "rejects inactive locations for new adjustments but allows completed retries" do
    first = adjust
    location.update!(active: false)
    expect(adjust).to eq(first)
    expect { adjust(idempotency_key: "new") }.to raise_error(SolidusMcp::ToolError, /active/)
    expect(item.reload.count_on_hand).to eq(5)
  end

  it "rejects untracked variants without reserving their request key" do
    variant.update!(track_inventory: false)
    expect { adjust }.to raise_error(SolidusMcp::ToolError, /tracking/)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
    variant.update!(track_inventory: true)
    expect(adjust).to include(count_on_hand_after: 5)
  end

  it "rejects globally disabled tracking" do
    previous = Spree::Config.track_inventory_levels
    Spree::Config.track_inventory_levels = false
    expect { adjust }.to raise_error(SolidusMcp::ToolError, /tracking/)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
  ensure
    Spree::Config.track_inventory_levels = previous
  end

  it "checks current record access on successful retries" do
    adjust
    restrict { |ability| ability.cannot :read, Spree::StockLocation, id: location.id }
    expect { adjust }.to raise_error(ActiveRecord::RecordNotFound)
    expect(item.reload.count_on_hand).to eq(5)
  end

  it "checks product and variant access" do
    restrict { |ability| ability.cannot :read, Spree::Product, id: product.id }
    expect { adjust }.to raise_error(ActiveRecord::RecordNotFound)
    restrict { |ability| ability.cannot :read, Spree::Variant, id: variant.id }
    expect { adjust }.to raise_error(ActiveRecord::RecordNotFound)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
  end

  it "checks stock item update and movement creation permissions" do
    restrict { |ability| ability.cannot :update, Spree::StockItem, id: item.id }
    expect { adjust }.to raise_error(ActiveRecord::RecordNotFound)
    restrict { |ability| ability.cannot :create, Spree::StockMovement, stock_item_id: item.id }
    expect { adjust }.to raise_error(SolidusMcp::AccessDenied)
    expect(item.reload.count_on_hand).to eq(0)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
  end

  it "enforces count attribute restrictions before and after the movement" do
    restrict { |ability| ability.cannot :update, Spree::StockItem, :count_on_hand }
    expect { adjust }.to raise_error(SolidusMcp::AccessDenied)
    expect(item.reload.count_on_hand).to eq(0)
    restrict { |ability| ability.cannot :update, Spree::StockItem, count_on_hand: 5 }
    expect { adjust }.to raise_error(SolidusMcp::AccessDenied)
    expect(item.reload.count_on_hand).to eq(0)
    expect(Spree::StockMovement.count).to eq(0)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
  end

  it "requires Solidus movement creation ability" do
    restrict { |ability| ability.cannot :create, Spree::StockMovement }
    expect { adjust }.to raise_error(SolidusMcp::AccessDenied)
  end

  it "rechecks grants after acquiring the stock item lock" do
    item
    allow_any_instance_of(Spree::StockItem).to receive(:with_lock).and_wrap_original do |method, &block|
      method.call do
        @saved.update!(permissions: [])
        block.call
      end
    end
    expect { adjust }.to raise_error(SolidusMcp::AccessDenied)
    expect(item.reload.count_on_hand).to eq(0)
    expect(SolidusMcp::StockAdjustment.count).to eq(0)
  end
  context "with independently committed concurrent requests" do
    self.use_transactional_tests = false

    before do
      @concurrent_arguments = arguments
      item
      @concurrent_token_id = token.id
      @concurrent_user_id = user.id
    end

    after do
      # These examples need separate database sessions and cannot use the usual
      # wrapping transaction. Remove only their own committed fixture records.
      SolidusMcp::StockAdjustment.where(connection_policy_id: @saved.id).delete_all
      variant_ids = Spree::Variant.where(product_id: product.id).pluck(:id)
      stock_ids = Spree::StockItem.where(variant_id: variant_ids).or(Spree::StockItem.where(stock_location_id: location.id)).pluck(:id)
      Spree::StockMovement.where(stock_item_id: stock_ids).delete_all
      Spree::StockItem.where(id: stock_ids).delete_all
      Spree::Price.where(variant_id: variant_ids).delete_all
      Spree::Variant.where(id: variant_ids).delete_all
      shipping_id = product.shipping_category_id
      Spree::Product.where(id: product.id).delete_all
      Spree::StockLocation.where(id: location.id).delete_all
      Spree::ShippingCategory.where(id: shipping_id).delete_all unless Spree::Product.where(shipping_category_id: shipping_id).exists?
      SolidusMcp::ConnectionPolicy.where(id: @saved.id).delete_all
      Doorkeeper::AccessToken.where(application_id: application.id).delete_all
      Doorkeeper::Application.where(id: application.id).delete_all
      TestUser.where(id: user.id).delete_all
    end

    def concurrently(*requests)
      expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
      ready = Queue.new
      start = Queue.new
      threads = requests.map do |request|
        Thread.new do
          Rails.application.executor.wrap do
            ActiveRecord::Base.connection_pool.with_connection do
              ready << true
              start.pop
              thread_token = Doorkeeper::AccessToken.find(@concurrent_token_id)
              thread_user = TestUser.find(@concurrent_user_id)
              described_class.execute(credential: SolidusMcp::Credential.new(thread_token, thread_user), **request)
            end
          end
        end
      end
      Timeout.timeout(20) do
        requests.length.times { ready.pop }
        requests.length.times { start << true }
        threads.map(&:value)
      end
    ensure
      threads&.each { |thread| thread.kill if thread.alive? }
      threads&.each(&:join)
    end

    it "applies simultaneous requests with the same key exactly once" do
      first, second = concurrently(@concurrent_arguments, @concurrent_arguments)
      expect(first).to eq(second)
      expect(item.reload.count_on_hand).to eq(5)
      expect(Spree::StockMovement.where(stock_item_id: item.id).count).to eq(1)
      expect(SolidusMcp::StockAdjustment.where(connection_policy_id: @saved.id).count).to eq(1)
    end

    it "serializes different keys against the same stock item without losing updates" do
      results = concurrently(@concurrent_arguments, @concurrent_arguments.merge(idempotency_key: "other-key"))
      expect(results.map { |result| result[:count_on_hand_after] }).to match_array([5, 10])
      expect(item.reload.count_on_hand).to eq(10)
      expect(Spree::StockMovement.where(stock_item_id: item.id).count).to eq(2)
    end
  end
end
