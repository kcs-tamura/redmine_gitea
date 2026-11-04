# frozen_string_literal: true

module GiteaHelper
  # Called by RepositoriesHelper#repository_field_tags as "#{scm.downcase}_field_tags".
  def gitea_field_tags(form, repository)
    render partial: 'redmine_gitea/gitea_fields', locals: { form: form, repository: repository }
  end

  def gitea_webhook_url(repository)
    "#{Setting.protocol}://#{Setting.host_name}#{repository.webhook_path}"
  end
end
