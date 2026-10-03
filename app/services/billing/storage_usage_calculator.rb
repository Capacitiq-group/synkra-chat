# Computes an account's actual storage usage in MB, by summing
# ActiveStorage blob byte_size across the two attachment surfaces that
# actually matter for volume: message attachments (Attachment model -
# the highest-frequency source, customer/agent files in conversations)
# and Captain::Document (Knowledge Base PDF/DOCX uploads for the
# Synkra AI Agent).
#
# NOT necessarily exhaustive of every ActiveStorage attachment in this
# app (e.g. account logos, user avatars aren't included) - those are
# one-per-entity and small, not the kind of volume a business would
# recognize as "their storage usage". If another genuinely
# volume-relevant attachment surface gets added later, it needs adding
# here explicitly - this does not discover attachment types
# automatically.
class Billing::StorageUsageCalculator
  def initialize(account)
    @account = account
  end

  def total_mb
    (total_bytes / 1.megabyte.to_f).round
  end

  private

  attr_reader :account

  def total_bytes
    attachment_bytes + captain_document_bytes
  end

  def attachment_bytes
    ActiveStorage::Blob
      .joins(:attachments)
      .where(active_storage_attachments: { record_type: 'Attachment' })
      .where(active_storage_attachments: { record_id: Attachment.where(account_id: account.id).select(:id) })
      .sum(:byte_size)
  end

  def captain_document_bytes
    return 0 unless defined?(Captain::Document)

    ActiveStorage::Blob
      .joins(:attachments)
      .where(active_storage_attachments: { record_type: 'Captain::Document' })
      .where(active_storage_attachments: { record_id: Captain::Document.where(account_id: account.id).select(:id) })
      .sum(:byte_size)
  end
end
