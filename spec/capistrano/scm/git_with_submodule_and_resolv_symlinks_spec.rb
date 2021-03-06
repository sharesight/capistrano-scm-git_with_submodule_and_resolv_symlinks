require 'spec_helper'

module Capistrano
  describe SCM::GitWithSubmoduleAndResolvSymlinks do
    subject { Capistrano::SCM::GitWithSubmoduleAndResolvSymlinks.new }

    # This allows us to easily use `set`, `fetch`, etc. in the examples.
    let(:env){ Capistrano::Configuration.env }

    # Stub the SSHKit backend so we can set up expectations without the plugin
    # actually executing any commands.
    let(:backend) { stub }
    before { SSHKit::Backend.stubs(:current).returns(backend) }

    # Mimic the deploy flow tasks so that the plugin can register its hooks.
    before do
      Rake::Task.define_task("deploy:new_release_path")
      Rake::Task.define_task("deploy:check")
      Rake::Task.define_task("deploy:set_current_revision")
    end

    # Clean up any tasks or variables that the plugin defined.
    after do
      Rake::Task.clear
      Capistrano::Configuration.reset!
    end

    describe "#set_defaults" do
      it "makes git_wrapper_path using application, stage, and local_user" do
        env.set(:tmp_dir, "/tmp")
        env.set(:application, "my_app")
        env.set(:stage, "staging")
        env.set(:local_user, "(Git Web User) via ShipIt")
        subject.set_defaults
        expect(env.fetch(:git_with_submodule_and_resolv_symlinks_wrapper_path)).to eq("/tmp/git-ssh-my_app-staging-(Git Web User) via ShipIt.sh")
      end
    end

    describe "#git" do
      it "should call git in the context, with arguments" do
        backend.expects(:execute).with(:git, :init)
        subject.git(:init)
      end
    end

    describe "#repo_mirror_exists?" do
      it "should call test for repo HEAD" do
        env.set(:repo_path, "/path/to/repo")
        backend.expects(:test).with " [ -d /path/to/repo/.git ] "

        subject.repo_mirror_exists?
      end
    end

    describe "#check_repo_is_reachable" do
      it "should test the repo url" do
        env.set(:repo_url, "url")
        backend.expects(:execute).with(:git, :'ls-remote', "url", "HEAD").returns(true)

        subject.check_repo_is_reachable
      end
    end

    describe "#clone_repo" do
      it "should run git clone" do
        env.set(:repo_url, "url")
        env.set(:repo_path, "path")
        backend.expects(:execute).with(:git, :clone, "url", "path")

        subject.clone_repo
      end
    end

    context "with username and password specified" do
      before do
        env.set(:git_http_username, "hello")
        env.set(:git_http_password, "topsecret")
        env.set(:repo_url, "https://example.com/repo.git")
        env.set(:repo_path, "path")
      end

      it "should include the credentials in the url" do
        backend.expects(:execute).with(:git, :clone, "https://hello:topsecret@example.com/repo.git", "path")
        subject.clone_repo
      end
    end

    describe "#update_mirror" do
      describe "with branch" do
        it "should run git remote set-url, git remote update, git checkout, git submodle update" do
          env.set(:branch, "real-branch")
          env.set(:repo_url, "url")

          backend.expects(:test).with(:git, :"rev-parse", "origin/real-branch").returns(true)
          backend.expects(:execute).with(:git, :remote, "set-url", "origin", "url")
          backend.expects(:execute).with(:git, :remote, :update, "--prune")
          backend.expects(:execute).with(:git, :checkout, "--detach", "origin/real-branch")
          backend.expects(:execute).with(:git, :submodule, :update, "--init")

          subject.update_mirror
        end
      end

      describe "with tag/commit" do
        it "should run git remote set-url, git remote update, git checkout, git submodle update" do
          env.set(:branch, "tag-or-commit")
          env.set(:repo_url, "url")

          backend.expects(:test).with(:git, :"rev-parse", "origin/tag-or-commit").returns(false)
          backend.expects(:execute).with(:git, :remote, "set-url", "origin", "url")
          backend.expects(:execute).with(:git, :remote, :update, "--prune")
          backend.expects(:execute).with(:git, :checkout, "--detach", "tag-or-commit")
          backend.expects(:execute).with(:git, :submodule, :update, "--init")

          subject.update_mirror
        end
      end
    end

    describe "#release" do
      it "should run rsync without a subtree" do
        env.set(:repo_path, "repo-path")
        env.set(:release_path, "release-path")

        backend.expects(:execute).with("rsync -ar --copy-links --exclude=.git\* repo-path/ release-path")

        subject.release
      end

      it "should run rsync with a subtree" do
        env.set(:repo_tree, "tree")
        env.set(:repo_path, "repo-path")
        env.set(:release_path, "release-path")

        backend.expects(:execute).with("rsync -ar --copy-links --exclude=.git\* repo-path/tree/ release-path")

        subject.release
      end
    end

    describe "#fetch_revision" do
      describe "with branch" do
        it "should capture git rev-list" do
          env.set(:branch, "real-branch")
          backend.expects(:test).with(:git, :"rev-parse", "origin/real-branch").returns(true)
          backend.expects(:capture).with(:git, "rev-list", "--max-count=1", "origin/real-branch").returns("81cec13b777ff46348693d327fc8e7832f79bf44")
          revision = subject.fetch_revision
          expect(revision).to eq("81cec13b777ff46348693d327fc8e7832f79bf44")
        end
      end

      describe "with tag/commit" do
        it "should capture git rev-list" do
          env.set(:branch, "tag-or-commit")
          backend.expects(:test).with(:git, :"rev-parse", "origin/tag-or-commit").returns(false)
          backend.expects(:capture).with(:git, "rev-list", "--max-count=1", "tag-or-commit").returns("81cec13b777ff46348693d327fc8e7832f79bf44")
          revision = subject.fetch_revision
          expect(revision).to eq("81cec13b777ff46348693d327fc8e7832f79bf44")
        end
      end
    end
  end
end
