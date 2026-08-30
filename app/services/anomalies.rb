class Anomalies
  def self.record!(batch:, type:, severity:, company: nil, establishment: nil, details: {})
    anomaly = DataAnomaly.find_or_initialize_by(
      channel: batch.channel, anomaly_type: type, company:, establishment:
    )
    changed_details = anomaly.persisted? && anomaly.details != details.stringify_keys
    anomaly.assign_attributes(
      severity:, details:, last_detected_at: Time.current,
      last_import_batch: batch, occurrences: anomaly.persisted? ? anomaly.occurrences + 1 : 1
    )
    anomaly.assign_attributes(first_detected_at: Time.current, first_import_batch: batch) if anomaly.new_record?
    anomaly.status = "aberta" if anomaly.status.blank? || (anomaly.status == "esperada" && changed_details)
    anomaly.save!
    anomaly
  end
end
