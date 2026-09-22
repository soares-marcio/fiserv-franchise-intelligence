# Uma concessão de escopo: o Master inteiro (sub_channel nulo) ou um MIC dele. O par
# (sub_channel_id, channel_id) tem FK composta no banco — conceder um MIC de outro Master
# é recusado lá, não só aqui.
class AccessGrant < ApplicationRecord
  belongs_to :user
  belongs_to :channel
  belongs_to :sub_channel, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  validate :sub_channel_belongs_to_channel

  scope :full_channels, -> { where(sub_channel_id: nil) }
  scope :partial, -> { where.not(sub_channel_id: nil) }

  def whole_channel? = sub_channel_id.nil?

  private

  def sub_channel_belongs_to_channel
    return if sub_channel.nil? || sub_channel.channel_id == channel_id

    errors.add(:sub_channel, "pertence a outro Master")
  end
end
