# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pending_tools"

RSpec.describe SolidusMcp::Tools::AttachProductImage do
  include_context "image tools"
  include_examples "a dedicated pending tool", "attach_product_image", -> { image_arguments }

  it "uploads to the product master and reuses the image for an identical request" do
    first = upload_image
    expect(first).to include(product_id: product.id, variant_id: product.master.id, content_type: "image/png")
    expect(Spree::Image.find(first[:id]).attachment.download).to eq(Base64.strict_decode64(png_base64))
    expect { expect(upload_image).to eq(first) }.not_to change(Spree::Image, :count)
    expect { upload_image(alt: "Different") }.to raise_error(SolidusMcp::ToolError, /different inputs/)
  end

  it "rejects foreign variants, remote inputs, bad content, unsafe names, and excessive data" do
    other = create_product(sku: "OTHER")
    expect { upload_image(variant_id: other.master.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { upload_image(data_base64: "bad") }.to raise_error(SolidusMcp::ToolError)
    expect { upload_image(content_type: "image/jpeg") }.to raise_error(SolidusMcp::ToolError)
    expect { upload_image(filename: "../pixel.png") }.to raise_error(SolidusMcp::ToolError)
    expect { upload_image(url: "https://example.test/pixel.png") }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    expect { upload_image(data_base64: "x" * 699053) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "authorizes image creation before upload" do
    restrict { |ability| ability.cannot :create, Spree::Image, viewable_id: product.master.id }
    expect { upload_image }.to raise_error(SolidusMcp::AccessDenied)
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  it "cleans storage and rolls back the image and request when saving fails" do
    uploaded_key = nil
    allow_any_instance_of(ActiveStorage::Blob).to receive(:upload_without_unfurling).and_wrap_original do |original, *args|
      uploaded_key = original.receiver.key
      original.call(*args)
    end
    allow_any_instance_of(Spree::Image).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
    expect { upload_image }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Spree::Image.count).to eq(0)
    expect(ActiveStorage::Blob.count).to eq(0)
    expect(SolidusMcp::ToolRequest.count).to eq(0)
    expect(ActiveStorage::Blob.service.exist?(uploaded_key)).to be(false)
  end
end
