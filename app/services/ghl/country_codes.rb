# frozen_string_literal: true

module Ghl
  # GoHighLevel espera el país en ISO 3166-1 alpha-2 ("EC"), pero `orders.country` guarda el texto
  # que escribió la persona en el formulario del SRI ("Ecuador"). Regla 6 de crm-gohighlevel:
  # normalizar antes de enviar y, si no matchea, enviar sin país (no bloquear el reporte).
  #
  # Tabla mínima: países hispanohablantes + los destinos más frecuentes del alumnado CLEV.
  # Si el valor no está acá, el orquestador loguea y omite el campo.
  module CountryCodes
    module_function

    MAPA = {
      "argentina" => "AR",
      "bolivia" => "BO",
      "brasil" => "BR",
      "brazil" => "BR",
      "canada" => "CA",
      "chile" => "CL",
      "colombia" => "CO",
      "costa rica" => "CR",
      "cuba" => "CU",
      "ecuador" => "EC",
      "el salvador" => "SV",
      "espana" => "ES",
      "espanha" => "ES",
      "spain" => "ES",
      "estados unidos" => "US",
      "united states" => "US",
      "usa" => "US",
      "guatemala" => "GT",
      "honduras" => "HN",
      "italia" => "IT",
      "italy" => "IT",
      "mexico" => "MX",
      "nicaragua" => "NI",
      "panama" => "PA",
      "paraguay" => "PY",
      "peru" => "PE",
      "puerto rico" => "PR",
      "republica dominicana" => "DO",
      "uruguay" => "UY",
      "venezuela" => "VE"
    }.freeze

    # Devuelve el alpha-2 o nil si no se puede resolver.
    def alpha2(valor)
      texto = valor.to_s.strip
      return nil if texto.blank?

      # Ya viene en alpha-2 (ej. "EC", "ec").
      return texto.upcase if texto.length == 2 && texto.match?(/\A[a-zA-Z]{2}\z/)

      MAPA[normalizar(texto)]
    end

    def normalizar(texto)
      # Quita tildes y colapsa espacios: "España" → "espana", "  Ecuador " → "ecuador".
      texto.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.squish
    end
  end
end
