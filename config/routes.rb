# frozen_string_literal: true

post 'redmine_gitea/:repository_id/webhook', to: 'redmine_gitea/webhooks#receive',
                                             as: 'redmine_gitea_webhook',
                                             constraints: { repository_id: /\d+/ }
