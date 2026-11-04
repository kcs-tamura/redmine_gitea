# frozen_string_literal: true

module RedmineGitea
  # Clones the mirror if needed, fetches from the remote and imports new changesets.
  class FetchJob < ActiveJob::Base
    queue_as :default

    def perform(repository_id)
      repository = Repository::Gitea.find_by(id: repository_id)
      return unless repository

      repository.scm.clone_unless_exists
      repository.fetch_changesets
    rescue Redmine::Scm::Adapters::CommandFailed => e
      Rails.logger.error "[redmine_gitea] sync failed for repository ##{repository_id}: #{e.message}"
    end
  end
end
