module Retention
  # Deletes attachments after attachment_days and test results after result_days,
  # keeping run and build rows (and their counts) forever. Runs are marked as they
  # are purged, so an interrupted purge resumes on the next call. Spec §4.1.
  class Purge
    BATCH_SIZE = 500
    PAUSE = 0.1

    def initialize(config: Retention.config, pause: PAUSE)
      @config = config
      @pause = pause
    end

    def call(now: Time.current, dry_run: false)
      @now = now
      @dry_run = dry_run
      @report = Report.zero
      @run_ids = Set.new
      purge_attachments
      purge_results
      purge_orphans
      @report.runs = @run_ids.size
      @report
    end

    private

    def attachment_cutoff = @now - @config.attachment_days.days
    def result_cutoff = @now - @config.result_days.days

    def purge_attachments
      each_batch(Run.where(attachments_purged_at: nil, created_at: ...attachment_cutoff)) do |ids|
        @report.attachments += attachments_for(ids).count
        next if @dry_run

        purge_attachment_files(ids)
        Run.where(id: ids).update_all(attachments_purged_at: @now)
      end
    end

    def purge_results
      each_batch(Run.where(results_purged_at: nil, created_at: ...result_cutoff)) do |ids|
        results = TestResult.where(run_id: ids)
        @report.results += results.count
        next if @dry_run

        purge_attachment_files(ids)
        # No wrapping transaction: it would hold SQLite's write lock while ingest runs.
        # Deleting is idempotent, so a crash before marking just re-selects the run next night.
        results.in_batches(of: BATCH_SIZE).delete_all
        Run.where(id: ids).update_all([ "results_purged_at = :now, attachments_purged_at = COALESCE(attachments_purged_at, :now)",
                                        { now: @now } ])
      end
    end

    def purge_orphans
      groups = ErrorGroup.where.missing(:test_results).where(last_seen_at: ...result_cutoff)
      # Quarantines (active or not) and their event trail outlive result retention (spec §5.2).
      cases = TestCase.where.missing(:test_results).where.missing(:quarantines).where(created_at: ...result_cutoff)
      @report.error_groups = @dry_run ? groups.count : delete_in_batches(groups)
      @report.test_cases = @dry_run ? cases.count : delete_in_batches(cases)
    end

    def each_batch(scope)
      first = true
      scope.in_batches(of: BATCH_SIZE) do |batch|
        sleep(@pause) unless first || @pause.zero?
        first = false
        ids = batch.ids
        @run_ids.merge(ids)
        yield ids
      end
    end

    def attachments_for(run_ids)
      ActiveStorage::Attachment.where(record_type: "TestResult", record_id: TestResult.where(run_id: run_ids).select(:id))
    end

    # File first, then rows: a failed file delete leaves the rows so the next night retries.
    def purge_attachment_files(run_ids)
      attachments_for(run_ids).includes(:blob).find_each do |attachment|
        attachment.blob.delete
        attachment.purge
      end
    end

    def delete_in_batches(scope)
      scope.in_batches(of: BATCH_SIZE).sum { |batch| batch.delete_all }
    end
  end
end
