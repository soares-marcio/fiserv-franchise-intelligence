module PublicIdentifier
  extend ActiveSupport::Concern

  def to_param
    uuid
  end

  class_methods do
    def find_param!(value)
      find_by!(uuid: value)
    end
  end
end
