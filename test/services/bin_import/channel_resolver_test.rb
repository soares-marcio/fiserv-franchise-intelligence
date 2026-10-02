require "test_helper"

# O REPORT_ID é a identidade do canal na planilha: se ele aparecer com outro CANAL, o
# arquivo é de outra carteira e importar misturaria duas bases.
class BinImport::ChannelResolverTest < ActiveSupport::TestCase
  # O canal novo volta sem salvar: quem o grava é a transação que grava os dados do arquivo,
  # para planilha que falha não deixar Master vazio.
  test "monta o canal na primeira planilha do REPORT_ID, sem gravá-lo" do
    channel = nil
    assert_no_difference -> { Channel.count } do
      channel = BinImport::ChannelResolver.call(organization: default_organization, report_id: "7788", name: "CANAL NOVO")
    end

    assert channel.new_record?
    assert_equal "7788", channel.external_id
    assert_equal "CANAL NOVO", channel.name
  end

  test "a segunda planilha do mesmo REPORT_ID reaproveita o canal" do
    first = BinImport::ChannelResolver.call(organization: default_organization, report_id: "7788", name: "CANAL NOVO")
    first.save!

    assert_no_difference -> { Channel.count } do
      assert_equal first, BinImport::ChannelResolver.call(organization: default_organization, report_id: "7788", name: "CANAL NOVO")
    end
  end

  test "recusa REPORT_ID que aparece com outro CANAL" do
    BinImport::ChannelResolver.call(organization: default_organization, report_id: "7788", name: "CANAL NOVO").save!

    error = assert_raises(ArgumentError) do
      BinImport::ChannelResolver.call(organization: default_organization, report_id: "7788", name: "OUTRA CARTEIRA")
    end

    assert_match(/já pertence ao canal/, error.message)
  end
end
