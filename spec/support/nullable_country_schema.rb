# frozen_string_literal: true

shared_examples "a required nullable country" do
  let(:schema) { SolidusMcp.registry.tools.fetch(tool_name).input_schema }
  let(:validator) { MCP::Tool::InputSchema.new(schema) }

  it "uses separate single-type branches for the nullable country" do
    expect(country_schema).not_to have_key(:type)
    expect(country_schema.fetch(:anyOf).map { |branch| branch.fetch(:type) }).to eq(%w[string null])
  end

  it "accepts a country code or explicit null" do
    ["CA", nil].each do |country|
      expect { validator.validate_arguments(arguments_for.call(country)) }.not_to raise_error
    end
  end

  it "rejects a non-string, non-null country" do
    expect { validator.validate_arguments(arguments_for.call(123)) }
      .to raise_error(MCP::Tool::InputSchema::ValidationError)
  end

  it "rejects an omitted country" do
    arguments = arguments_for.call(nil)
    country_container.call(arguments).delete(:country_iso)
    expect { validator.validate_arguments(arguments) }
      .to raise_error(MCP::Tool::InputSchema::ValidationError)
  end
end
