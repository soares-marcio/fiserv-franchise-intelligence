require "test_helper"

class Operations::ConfirmDuplicateTest < ActiveSupport::TestCase
  test "links a duplicate EC without merging" do
    channel = Channel.create!(external_id: "1", canal: "MASTER")
    company = Company.create!(cnpj: "12345678000195")
    primary = Establishment.create!(ec: "32546997", company:, channel:)
    duplicate = Establishment.create!(ec: "92546997", company:, channel:)

    Operations::ConfirmDuplicate.call(establishment: duplicate, primary:)

    assert_equal primary.id, duplicate.reload.primary_establishment_id
    assert_equal 2, Establishment.where(company:).count
  end

  test "rejects a principal from another CNPJ" do
    channel = Channel.create!(external_id: "1", canal: "MASTER")
    one = Establishment.create!(ec: "12345678", company: Company.create!(cnpj: "12345678000195"), channel:)
    other = Establishment.create!(ec: "12345679", company: Company.create!(cnpj: "99945678000195"), channel:)

    error = assert_raises(ArgumentError) { Operations::ConfirmDuplicate.call(establishment: one, primary: other) }
    assert_match(/mesmo CNPJ/, error.message)
  end
end
