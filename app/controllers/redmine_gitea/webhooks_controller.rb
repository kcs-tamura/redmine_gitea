# frozen_string_literal: true

require 'openssl'

module RedmineGitea
  # Receives Gitea / Forgejo webhooks.
  #
  # The request is authenticated only by the HMAC-SHA256 signature of the raw body
  # (X-Gitea-Signature / X-Forgejo-Signature) with the repository's webhook secret.
  # A repository without a secret never accepts webhooks.
  class WebhooksController < ActionController::Base
    skip_forgery_protection

    SYNC_EVENTS = %w[push create delete].freeze

    def receive
      repository = Repository::Gitea.find_by(id: params[:repository_id])
      return head(:not_found) unless repository
      return head(:forbidden) unless valid_signature?(repository.webhook_secret)

      if SYNC_EVENTS.include?(event_name)
        RedmineGitea::FetchJob.perform_later(repository.id)
        head :accepted
      else
        head :ok
      end
    end

    private

    def event_name
      request.headers['X-Gitea-Event'].presence || request.headers['X-Forgejo-Event'].to_s
    end

    def valid_signature?(secret)
      return false if secret.blank?

      given = (request.headers['X-Gitea-Signature'].presence ||
               request.headers['X-Forgejo-Signature'].presence).to_s.strip.downcase
      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post.to_s)
      given.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(given, expected)
    end
  end
end
