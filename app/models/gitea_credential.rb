# frozen_string_literal: true

# Webhook secret of a Repository::Gitea, stored encrypted with Redmine's database cipher key.
class GiteaCredential < ActiveRecord::Base
  include Redmine::Ciphering

  belongs_to :repository, class_name: 'Repository::Gitea', inverse_of: :gitea_credential

  def webhook_secret=(secret)
    write_ciphered_attribute(:webhook_secret, secret)
  end

  def webhook_secret
    read_ciphered_attribute(:webhook_secret)
  end
end
