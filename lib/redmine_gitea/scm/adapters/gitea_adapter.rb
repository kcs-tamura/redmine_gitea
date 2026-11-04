# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'open3'
require 'uri'

module RedmineGitea
  module Scm
    module Adapters
      # Git adapter that keeps a local bare mirror of a remote Gitea/Forgejo repository.
      #
      # All read operations (log, entries, diff, ...) are inherited from Redmine's GitAdapter and
      # run against the local mirror (root_url). Only clone/fetch talk to the remote.
      #
      # The access token is never written to disk or put on the command line: it is handed to git
      # as an http.extraHeader through GIT_CONFIG_* environment variables of that one process.
      class GiteaAdapter < Redmine::Scm::Adapters::GitAdapter
        REFSPECS = %w[+refs/heads/*:refs/heads/* +refs/tags/*:refs/tags/*].freeze

        def self.repositories_root
          Rails.root.join('repositories', 'gitea')
        end

        # Local mirror path derived from the remote URL:
        #   https://git.example.com/Owner/Repo.git -> <root>/git.example.com/owner/repo.git
        def self.local_path_for(url)
          uri = URI.parse(url.to_s)
          segments = uri.path.to_s.split('/').reject(&:blank?)
          return nil if uri.host.blank? || segments.size < 2

          owner = sanitize(segments[-2])
          repo  = sanitize(segments[-1].sub(/\.git\z/i, ''))
          repositories_root.join(sanitize(uri.host), owner, "#{repo}.git").to_s
        rescue URI::InvalidURIError
          nil
        end

        def self.sanitize(segment)
          segment.to_s.downcase.gsub(/[^a-z0-9._-]/, '_').sub(/\A\.+/, '_')
        end

        attr_reader :remote_url

        def initialize(url, root_url, access_token, path_encoding = nil)
          @remote_url   = url
          @access_token = access_token
          local = self.class.local_path_for(url)
          # Inherited git commands use `--git-dir root_url`.
          super(url, local || root_url, nil, nil, path_encoding)
        end

        def cloned?
          root_url.present? && File.exist?(File.join(root_url, 'HEAD'))
        end

        # Create the bare mirror if missing. Safe to call concurrently.
        def clone_unless_exists
          with_lock do
            next if cloned?

            FileUtils.mkdir_p(File.dirname(root_url))
            tmp = "#{root_url}.tmp-#{Process.pid}"
            FileUtils.rm_rf(tmp)
            run_remote_git('clone', '--bare', '--quiet', remote_url, tmp)
            File.rename(tmp, root_url)
          ensure
            FileUtils.rm_rf(tmp) if tmp && File.exist?(tmp)
          end
        end

        # Update branches and tags of the mirror from the remote (prunes deleted ones).
        def fetch_remote
          return unless cloned?

          with_lock do
            run_remote_git('--git-dir', root_url, 'fetch', '--quiet', '--prune', remote_url, *REFSPECS)
          end
        end

        def remove_local_mirror
          return unless root_url.present?

          root = self.class.repositories_root.to_s
          path = File.expand_path(root_url)
          # Never delete anything outside our own mirror root.
          return unless path.start_with?(root + File::SEPARATOR)

          with_lock { FileUtils.rm_rf(path) }
          FileUtils.rm_f(lock_path)
        end

        private

        def lock_path
          "#{root_url}.lock"
        end

        def with_lock
          FileUtils.mkdir_p(File.dirname(lock_path))
          File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |f|
            f.flock(File::LOCK_EX)
            yield
          end
        end

        def run_remote_git(*args)
          out, status = Open3.capture2e(git_env, self.class.client_command, *args)
          return out if status.success?

          raise Redmine::Scm::Adapters::CommandFailed,
                "git #{args.include?('clone') ? 'clone' : 'fetch'} failed (exit #{status.exitstatus}): #{scrub(out).strip}"
        end

        # Keep any GIT_CONFIG_* already set for the process (e.g. safe.directory) and append ours.
        def git_env
          env = { 'GIT_TERMINAL_PROMPT' => '0', 'GIT_ASKPASS' => 'true', 'GIT_LFS_SKIP_SMUDGE' => '1' }
          return env if @access_token.blank?

          index = ENV['GIT_CONFIG_COUNT'].to_i
          credential = Base64.strict_encode64("redmine:#{@access_token}")
          env.merge(
            'GIT_CONFIG_COUNT' => (index + 1).to_s,
            "GIT_CONFIG_KEY_#{index}" => 'http.extraHeader',
            "GIT_CONFIG_VALUE_#{index}" => "Authorization: Basic #{credential}"
          )
        end

        def scrub(text)
          text = text.to_s
          text = text.gsub(@access_token, '[FILTERED]') if @access_token.present?
          text.gsub(%r{(https?://)[^/@\s]+@}, '\1[FILTERED]@')
        end
      end
    end
  end
end
