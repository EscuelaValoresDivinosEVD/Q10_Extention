# frozen_string_literal: true

# Orden del funnel público de inscripción a cursos.
#
# Modelo separado de `Payment` a propósito (ADR-001): aquel está acoplado al dominio de créditos
# Q10 (codigo_persona, consecutivo_credito, cuotas, q10_reported) y su ciclo de vida reporta a Q10;
# esta orden reporta a GoHighLevel y habla el vocabulario de negocio del panel de inscripciones.
class Order < ApplicationRecord
  STATUSES = %w[pending paid rejected failed].freeze
  ESTADOS_FINALES = %w[paid rejected failed].freeze
  OPTION_KINDS = %w[reserva parcial completo].freeze

  # Mapeo desde lo que notifica el webhook de Pagomedios — mismo principio que
  # map_pagomedios_status del flujo de deudas, con vocabulario de negocio (ADR-005).
  # Pagomedios notifica el estado como código numérico ("1"/"2"/"3"); se aceptan además
  # los alias textuales por robustez. Un estado desconocido NO se mapea: la orden queda
  # como está y se loguea (comportamiento conservador).
  PAGOMEDIOS_STATUS_MAP = {
    "1" => "paid",
    "2" => "rejected",
    "3" => "rejected",   # `reversed` colapsa en `rejected` (ADR-005)
    "authorized" => "paid",
    "rejected" => "rejected",
    "reversed" => "rejected",
    "failed" => "failed",
    "pending" => "pending"
  }.freeze

  # El snapshot se escribe una sola vez al crear la orden y nunca cambia (regla 2 / ADR-002).
  # Sin belongs_to: no hay tabla local de curso/opción a la cual apuntar (ADR-008).
  attr_readonly :q10_course_code, :option_code, :course_slug, :course_name,
                :option_kind, :option_label, :course_edition_year,
                :amount, :amount_without_tax, :amount_with_tax, :tax_value, :tax_rate

  validates :reference, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :q10_course_code, :option_code, :course_slug, :course_name,
            :option_kind, :option_label, presence: true
  validates :first_name, :last_name, :identification_type_code, :identification_number,
            :email, :phone, :address, :city, :country, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate  :desglose_iva_cuadra

  scope :pagadas, -> { where(status: "paid") }
  scope :pendientes, -> { where(status: "pending") }
  scope :recientes, -> { order(created_at: :desc) }
  scope :crm_pendientes, -> { pagadas.where(crm_reported: false) }
  scope :crm_reportadas, -> { where(crm_reported: true) }
  scope :crm_sin_reportar, -> { crm_pendientes.where(crm_error: nil) }
  scope :crm_con_error, -> { crm_pendientes.where.not(crm_error: nil) }
  scope :del_curso, ->(codigo) { where(q10_course_code: codigo.to_s) if codigo.present? }
  scope :con_estado, ->(estado) { where(status: estado.to_s) if estado.present? }
  scope :desde, ->(fecha) { where(created_at: fecha.beginning_of_day..) if fecha.present? }
  scope :hasta, ->(fecha) { where(created_at: ..fecha.end_of_day) if fecha.present? }
  scope :entre, ->(inicio, fin) { desde(inicio).hasta(fin) }

  class << self
    # Referencia legible con prefijo propio: distingue órdenes de inscripción (INSC-) de los
    # pagos de deudas (CLEV-) en logs y soporte. Formato espejo de `build_reference` del repo.
    def build_reference
      "INSC-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3).upcase}"
    end

    # Crea (sin guardar) la orden a partir de un snapshot ya revalidado: disponibilidad vía
    # Q10::CourseCatalog#option_snapshot + precio vía Inscripcion::PricingSource. Ambos snapshots
    # se fusionan antes de llegar acá.
    def build_from_snapshot(snapshot, atributos_facturacion = {})
      snapshot = snapshot.symbolize_keys
      desglose = SubscriptionAmountCalculator.desglose_iva(snapshot[:amount], snapshot[:tax_rate])

      new(
        reference: build_reference,
        return_token: SecureRandom.hex(16),
        q10_course_code: snapshot[:course_code],
        option_code: snapshot[:option_code],
        course_slug: slug_para(snapshot),
        course_name: snapshot[:course_name],
        option_kind: snapshot[:option_kind],
        option_label: snapshot[:option_label],
        course_edition_year: snapshot[:course_edition_year],
        amount: snapshot[:amount],
        currency: snapshot[:currency].presence || "USD",
        tax_rate: snapshot[:tax_rate] || 0.0,
        **desglose,
        **atributos_facturacion.symbolize_keys
      )
    end

    def slug_para(snapshot)
      snapshot[:course_name].to_s.parameterize.presence ||
        snapshot[:course_code].to_s.parameterize
    end
  end

  def pagada? = status == "paid"
  def pendiente? = status == "pending"
  def final? = ESTADOS_FINALES.include?(status)

  def nombre_completo
    [ first_name, last_name ].compact_blank.join(" ")
  end

  def descripcion_compra
    [ course_name, option_label ].compact_blank.join(" — ")
  end

  # Estado del reporte al CRM que muestra el panel — derivado, no persistido.
  def crm_status
    return :no_aplica unless pagada?
    return :reportado if crm_reported?

    crm_error.present? ? :error : :pendiente
  end

  # Tag curso-año enviado a GoHighLevel (regla 4 de crm-gohighlevel).
  # El año sale del snapshot de Q10 si está disponible; si no, del año del pago.
  def tag_crm
    return nil if course_slug.blank?

    anio = course_edition_year.presence || transaction_at&.year || created_at&.year || Time.current.year
    "#{course_slug}-#{anio}"
  end

  def needs_crm_report? = pagada? && !crm_reported?

  private

  def desglose_iva_cuadra
    return if amount.blank?

    suma = amount_with_tax.to_d + amount_without_tax.to_d + tax_value.to_d
    return if suma == amount.to_d

    errors.add(:amount, "no cuadra con el desglose de IVA (#{suma} ≠ #{amount})")
  end
end
