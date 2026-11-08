# frozen_string_literal: true

class LoadingSerializer
  def self.call(record, context:)
    {id: record.id, loaded: true}
  end
end
