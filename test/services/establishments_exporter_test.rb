require "test_helper"
require "csv"

class EstablishmentsExporterTest < ActiveSupport::TestCase
  setup do
    @channel = Channel.create!(organization: default_organization, external_id: "1478", name: "MASTER")
    @company = Company.create!(cnpj: "12345678000195")
    template = BinImport::Template.register!
    @batch = ImportBatch.create!(channel: @channel, import_template: template,
      source_filename: "manual", file_checksum: "seed-#{SecureRandom.hex(4)}", status: "validated")
  end

  # O cadastro que diverge entre ECs sai pelo EC de referência — o que não é duplicata de
  # outro —, a mesma regra da tela. Sem isso, arquivo e tela contariam clientes diferentes.
  test "o cadastro vem do EC de referência, não do primeiro da lista" do
    reference = create_ec("11111111", "MIC GOIANIA 4", trade_name: "PADARIA CENTRAL")
    duplicate_one = create_ec("22222222", "MIC CAMPINA GRANDE", trade_name: "OUTRO NOME",
      primary_establishment: reference)

    row = CSV.parse(exporter([ duplicate_one, reference ]).to_csv, headers: true).first

    assert_equal "PADARIA CENTRAL", row["Nome fantasia"]
    assert_equal "12.345.678/0001-95", row["CNPJ"]
    assert_equal "2", row["Quantidade de ECs"]
    assert_equal "22222222 · 11111111", row["ECs"], "os ECs saem na ordem recebida"
  end

  # Um CNPJ pode ter ECs em MICs diferentes, e a tela lista todos: o arquivo faz igual, em
  # vez de escolher um em silêncio.
  test "os MICs do cliente saem todos, sem repetir" do
    first_item = create_ec("11111111", "MIC GOIANIA 4")
    second = create_ec("22222222", "MIC CAMPINA GRANDE", primary_establishment: first_item)
    third = create_ec("33333333", "MIC GOIANIA 4", primary_establishment: first_item)

    row = CSV.parse(exporter([ first_item, second, third ]).to_csv, headers: true).first

    assert_equal "MIC GOIANIA 4 · MIC CAMPINA GRANDE", row["MIC"]
    assert_equal "MASTER", row["Master"]
  end

  test "a busca da tela fica escrita na nota do arquivo" do
    create_ec("11111111", "MIC GOIANIA 4")

    exporter = EstablishmentsExporter.new([ @company ],
      establishments_by_company: { @company => @company.establishments.to_a }, query: "PADARIA")

    assert_match(/busca: PADARIA/, exporter.send(:note))
  end

  private

  def create_ec(ec, mic, primary_establishment: nil, trade_name: "PADARIA CENTRAL")
    sub_channel = @channel.sub_channels.find_or_create_by!(name: mic)
    establishment = Establishment.create!(ec:, company: @company, channel: @channel,
      primary_establishment:)
    MapSnapshot.create!(import_batch: @batch, channel: @channel, sub_channel:, establishment:,
      trade_name:, legal_name: "PADARIA CENTRAL LTDA", contract_status: "Active",
      city: "GOIANIA", state: "GO")
    establishment
  end

  def exporter(establishments)
    EstablishmentsExporter.new([ @company ],
      establishments_by_company: { @company => establishments })
  end
end
