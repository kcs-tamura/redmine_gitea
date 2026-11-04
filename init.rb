# frozen_string_literal: true

Redmine::Plugin.register :redmine_gitea do
  name        'Redmine Gitea'
  author      'Kitsune Creative Studio'
  description 'Connect Gitea / Forgejo repositories to Redmine by URL (bare mirror + signed push webhook)'
  version     '0.1.0' # keep in sync with RedmineGitea::VERSION
  author_url  'https://www.kitsune-creative.studio/'
  url         'https://github.com/kcs-tamura/redmine_gitea'
  requires_redmine version_or_higher: '5.0.0'
end

Redmine::Scm::Base.add('Gitea')

Rails.application.config.after_initialize do
  RepositoriesController.helper GiteaHelper
end
