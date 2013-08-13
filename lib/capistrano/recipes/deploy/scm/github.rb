require 'capistrano/recipes/deploy/scm/base'

module Capistrano
  module Deploy
    module SCM

      class Github < Base
        # Sets the default command name for this SCM on your *local* machine.
        # Users may override this by setting the :scm_command variable.
        default_command "git"

        # When referencing "head", use the branch we want to deploy or, by
        # default, Git's reference of HEAD (the latest changeset in the default
        # branch, usually called "master").
        def head
          variable(:branch) || 'HEAD'
        end

        def origin
          variable(:remote) || 'origin'
        end

        # Performs a clone on the remote machine, then checkout on the branch
        # you want to deploy.
        def checkout(revision, destination)
          git    = command
          remote = origin

          args = []

          # Add an option for the branch name so :git_shallow_clone works with branches
          args << "-b #{variable(:branch)}" unless variable(:branch).nil? || variable(:branch) == revision
          args << "-o #{remote}" unless remote == 'origin'
          if depth = variable(:git_shallow_clone)
            args << "--depth #{depth}"
          end

          execute = []
          execute << "#{git} clone #{verbose} #{args.join(' ')} #{variable(:repository)} #{destination}"

          if(variable(:pull_request_number)) 
            execute << "cd #{destination} && #{git} fetch #{verbose} #{remote} +refs/pull/#{variable(:pull_request_number)}/merge: && #{git} checkout -qf FETCH_HEAD"
          else
            execute << "cd #{destination} && #{git} checkout #{verbose} -b deploy #{revision}"
          end

          if variable(:git_enable_submodules)
            execute << "#{git} submodule #{verbose} init"
            execute << "#{git} submodule #{verbose} sync"
            if false == variable(:git_submodules_recursive)
              execute << "#{git} submodule #{verbose} update --init"
            else
              execute << %Q(export GIT_RECURSIVE=$([ ! "`#{git} --version`" \\< "git version 1.6.5" ] && echo --recursive))
              execute << "#{git} submodule #{verbose} update --init $GIT_RECURSIVE"
            end
          end

          execute.compact.join(" && ").gsub(/\s+/, ' ')
        end

        # An expensive export. Performs a checkout as above, then
        # removes the repo.
        def export(revision, destination)
          checkout(revision, destination) << " && rm -Rf #{destination}/.git"
        end

        # Merges the changes to 'head' since the last fetch, for remote_cache
        # deployment strategy
        def sync(revision, destination)
          git     = command
          remote  = origin

          execute = []
          execute << "cd #{destination}"

          # Use git-config to setup a remote tracking branches. Could use
          # git-remote but it complains when a remote of the same name already
          # exists, git-config will just silenty overwrite the setting every
          # time. This could cause wierd-ness in the remote cache if the url
          # changes between calls, but as long as the repositories are all
          # based from each other it should still work fine.
          if remote != 'origin'
            execute << "#{git} config remote.#{remote}.url #{variable(:repository)}"
            execute << "#{git} config remote.#{remote}.fetch +refs/heads/*:refs/remotes/#{remote}/*"
          end

          # since we're in a local branch already, just reset to specified revision rather than merge
          if(variable(:pull_request_number)) 
            execute << "#{git} fetch #{verbose} #{remote} +refs/pull/#{variable(:pull_request_number)}/merge: && #{git} checkout -qf FETCH_HEAD"
          else
            execute << "#{git} fetch #{verbose} #{remote} && #{git} fetch --tags #{verbose} #{remote} && #{git} reset #{verbose} --hard #{revision}"
          end

          if variable(:git_enable_submodules)
            execute << "#{git} submodule #{verbose} init"
            execute << "#{git} submodule #{verbose} sync"
            if false == variable(:git_submodules_recursive)
              execute << "#{git} submodule #{verbose} update --init"
            else
              execute << %Q(export GIT_RECURSIVE=$([ ! "`#{git} --version`" \\< "git version 1.6.5" ] && echo --recursive))
              execute << "#{git} submodule #{verbose} update --init $GIT_RECURSIVE"
            end
          end

          # Make sure there's nothing else lying around in the repository (for
          # example, a submodule that has subsequently been removed).
          execute << "#{git} clean #{verbose} -d -x -f"

          execute.join(" && ")
        end

        # Returns a string of diffs between two revisions
        def diff(from, to=nil)
          return scm :diff, from unless to
          scm :diff, "#{from}..#{to}"
        end

        # Returns a log of changes between the two revisions (inclusive).
        def log(from, to=nil)
          scm :log, "#{from}..#{to}"
        end

        # Getting the actual commit id, in case we were passed a tag
        # or partial sha or something - it will return the sha if you pass a sha, too
        def query_revision(revision)
          raise ArgumentError, "Deploying remote branches is no longer supported.  Specify the remote branch as a local branch for the git repository you're deploying from (ie: '#{revision.gsub('origin/', '')}' rather than '#{revision}')." if revision =~ /^origin\//
          return revision if revision =~ /^[0-9a-f]{40}$/
          command = scm('ls-remote', repository, revision)
          result = yield(command)
          revdata = result.split(/[\t\n]/)
          newrev = nil
          revdata.each_slice(2) do |refs|
            rev, ref = *refs
            if ref.sub(/refs\/.*?\//, '').strip == revision.to_s
              newrev = rev
              break
            end
          end
          return newrev if newrev =~ /^[0-9a-f]{40}$/

          # If sha is not found on remote, try expanding from local repository
          command = scm('rev-parse --revs-only', origin + '/' + revision)
          newrev = yield(command).to_s.strip

          raise "Unable to resolve revision for '#{revision}' on repository '#{repository}'." unless newrev =~ /^[0-9a-f]{40}$/
          return newrev
        end

        def command
          # For backwards compatibility with 1.x version of this module
          variable(:git) || super
        end

        # Determines what the response should be for a particular bit of text
        # from the SCM. Password prompts, connection requests, passphrases,
        # etc. are handled here.
        def handle_data(state, stream, text)
          host = state[:channel][:host]
          logger.info "[#{host} :: #{stream}] #{text}"
          case text
          when /\bpassword.*:/i
            # git is prompting for a password
            unless pass = variable(:scm_password)
              pass = Capistrano::CLI.password_prompt
            end
            %("#{pass}"\n)
          when %r{\(yes/no\)}
            # git is asking whether or not to connect
            "yes\n"
          when /passphrase/i
            # git is asking for the passphrase for the user's key
            unless pass = variable(:scm_passphrase)
              pass = Capistrano::CLI.password_prompt
            end
            %("#{pass}"\n)
          when /accept \(t\)emporarily/
            # git is asking whether to accept the certificate
            "t\n"
          end
        end

        private

          # If verbose output is requested, return nil, otherwise return the
          # command-line switch for "quiet" ("-q").
          def verbose
            variable(:scm_verbose) ? nil : "-q"
          end
      end
    end
  end
end