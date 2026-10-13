require "test_helper"

class FrontendSecurityTest < ActionDispatch::IntegrationTest
  DANGEROUS_DOM_SINKS = /
    \.innerHTML\s*=|
    \.outerHTML\s*=|
    insertAdjacentHTML\s*\(|
    document\.write\s*\(|
    \beval\s*\(|
    new\s+Function\s*\(
  /x

  test "controllers próprios não montam HTML por sinks executáveis" do
    controllers = Rails.root.glob("app/javascript/controllers/*.js")
    findings = controllers.filter_map do |path|
      match = path.read.match(DANGEROUS_DOM_SINKS)
      "#{path.relative_path_from(Rails.root)}: #{match[0]}" if match
    end

    assert_empty findings, findings.join("\n")
  end

  test "consulta maliciosa continua texto inerte na busca comum e no Turbo Frame" do
    import_synthetic_workbook
    payload = %(<img src=x onerror="window.__xss = true"><script>alert(1)</script>)

    [ {}, { "Turbo-Frame" => "global-search" } ].each do |headers|
      get search_path(q: payload), headers: headers

      assert_response :success
      assert_select "script", text: /alert\(1\)/, count: 0
      assert_select "img[onerror]", count: 0
      assert_not_includes response.body, payload
      assert_includes response.body, ERB::Util.html_escape(payload)
    end
  end
end
