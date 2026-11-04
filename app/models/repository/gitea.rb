# frozen_string_literal: true

# Gitea / Forgejo repository registered by its clone URL.
#
# Redmine keeps a bare mirror under <Rails.root>/repositories/gitea and reads history from it.
# The mirror is created and refreshed by a background job (RedmineGitea::FetchJob), triggered on
# creation and by Gitea's push webhook. Viewing the repository also refreshes it once cloned.
class Repository::Gitea < ::Repository::Git
  has_one :gitea_credential, foreign_key: :repository_id, dependent: :destroy, inverse_of: :repository
  accepts_nested_attributes_for :gitea_credential

  safe_attributes 'access_token', 'webhook_secret'

  validate :validate_remote_url

  before_validation :generate_webhook_secret, on: :create
  before_save :assign_local_root_url
  after_commit :enqueue_sync, on: %i[create update]
  after_destroy_commit :remove_local_mirror

  def self.scm_adapter_class
    RedmineGitea::Scm::Adapters::GiteaAdapter
  end

  def self.scm_name
    'Gitea'
  end

  # Repository::Git renames "url" to "Path to repository"; we want the plain label.
  def self.human_attribute_name(attribute_key_name, *args)
    Repository.human_attribute_name(attribute_key_name, *args)
  end

  def scm
    @scm ||= self.class.scm_adapter_class.new(url, root_url, access_token, path_encoding)
  end

  # Refresh the mirror and import new commits. If the mirror does not exist yet, cloning is
  # left to the background job so that a page view never blocks on a full clone.
  def fetch_changesets
    if scm.cloned?
      scm.fetch_remote
      super
    else
      RedmineGitea::FetchJob.perform_later(id) if persisted?
    end
  end

  def cloned?
    scm.cloned?
  end

  def access_token=(token)
    self.password = token
  end

  def access_token
    password
  end

  # Blank input never clears an existing secret (the edit form submits an empty field when the
  # user focuses it without typing). New repositories get a generated secret instead.
  def webhook_secret=(secret)
    return if secret.blank?

    build_gitea_credential if gitea_credential.blank?
    gitea_credential.webhook_secret = secret
  end

  def webhook_secret
    gitea_credential&.webhook_secret
  end

  def webhook_path
    "/redmine_gitea/#{id}/webhook"
  end

  private

  # A repository is always created with a secret so the webhook can be configured right away.
  def generate_webhook_secret
    self.webhook_secret = SecureRandom.hex(32) if webhook_secret.blank?
  end

  def validate_remote_url
    uri = URI.parse(url.to_s)
    unless uri.is_a?(URI::HTTP) && uri.host.present? && self.class.scm_adapter_class.local_path_for(url)
      errors.add(:url, :invalid)
    end
  rescue URI::InvalidURIError
    errors.add(:url, :invalid)
  end

  def assign_local_root_url
    @scm = nil if will_save_change_to_url? || will_save_change_to_password?
    self.root_url = self.class.scm_adapter_class.local_path_for(url).to_s
  end

  def enqueue_sync
    return unless saved_change_to_id? || saved_change_to_url? || saved_change_to_password?

    RedmineGitea::FetchJob.perform_later(id)
  end

  def remove_local_mirror
    scm.remove_local_mirror
  rescue StandardError => e
    Rails.logger.warn "[redmine_gitea] could not remove local mirror for repository ##{id}: #{e.class}: #{e.message}"
  end
end
