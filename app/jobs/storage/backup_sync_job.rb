module Storage
  # Daily sync of new or changed objects from the primary Z1 bucket
  # (synkra-chat) to a backup Z1 bucket (synkra-chat-backup). One-way:
  # backup is read-only. Never deletes from primary. Never syncs back.
  #
  # Idempotent and resumable. Uses S3 list_objects_v2 to walk every key.
  # If the job dies partway, the next run picks up where it left off
  # because already_backed_up? checks the backup ETag before re-copying.
  #
  # Time-boxed to MAX_OBJECTS_PER_RUN so a large backlog cannot hold a
  # Sidekiq thread indefinitely. Runs on :scheduled_jobs queue.
  class BackupSyncJob < ApplicationJob
    queue_as :scheduled_jobs

    MAX_OBJECTS_PER_RUN = 1_000

    def perform
      return unless configured?

      copied = 0
      scanned = 0

      client.list_objects_v2(bucket: primary_bucket).each_page do |page|
        page.contents.each do |obj|
          scanned += 1
          break if copied >= MAX_OBJECTS_PER_RUN
          next if already_backed_up?(obj.key, obj.etag)
          copy_object(obj)
          copied += 1
        end
        break if copied >= MAX_OBJECTS_PER_RUN
      end

      Rails.logger.info(
        "[StorageBackup] Sync complete. Scanned=#{scanned} Copied=#{copied} Limit=#{MAX_OBJECTS_PER_RUN}"
      )
    rescue StandardError => e
      Rails.logger.error "[StorageBackup] Sync failed: #{e.class}: #{e.message}"
    end

    private

    def configured?
      primary_bucket.present? &&
        backup_bucket.present? &&
        ENV['STORAGE_ACCESS_KEY_ID'].present? &&
        ENV['STORAGE_SECRET_ACCESS_KEY'].present?
    end

    def primary_bucket
      ENV.fetch('STORAGE_BUCKET_NAME', 'synkra-chat')
    end

    def backup_bucket
      ENV.fetch('STORAGE_BACKUP_BUCKET_NAME', 'synkra-chat-backup')
    end

    def client
      @client ||= Aws::S3::Client.new(
        access_key_id: ENV.fetch('STORAGE_ACCESS_KEY_ID'),
        secret_access_key: ENV.fetch('STORAGE_SECRET_ACCESS_KEY'),
        region: ENV.fetch('STORAGE_REGION'),
        endpoint: ENV.fetch('STORAGE_ENDPOINT'),
        force_path_style: ENV.fetch('STORAGE_FORCE_PATH_STYLE', 'true') == 'true'
      )
    end

    # Cheap check: does the object exist in the backup bucket with the
    # same ETag? If the primary object has been overwritten (new content,
    # new ETag), this returns false and we re-copy.
    def already_backed_up?(key, etag)
      head = client.head_object(bucket: backup_bucket, key: key)
      head.etag == etag
    rescue Aws::S3::Errors::NotFound
      false
    rescue StandardError => e
      Rails.logger.warn "[StorageBackup] head_object failed for #{key}: #{e.message}"
      false
    end

    def copy_object(obj)
      client.copy_object(
        bucket: backup_bucket,
        key: obj.key,
        copy_source: "/#{primary_bucket}/#{CGI.escape(obj.key)}",
        metadata_directive: 'COPY'
      )
    rescue StandardError => e
      Rails.logger.warn "[StorageBackup] copy failed for #{obj.key}: #{e.message}"
    end
  end
end
