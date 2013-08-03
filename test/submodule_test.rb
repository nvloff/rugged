require 'test_helper'

class SubmoduleTest < Rugged::SubmoduleTestCase
  def setup
    super
    @repo = setup_submodule
  end

  class TestException < StandardError
  end

  def test_submodule_simple_lookup
    # lookup pending change in .gitmodules that is not in HEAD
    assert Rugged::Submodule.lookup(@repo, 'sm_added_and_uncommited')

    # lookup pending change in .gitmodules that is neither in HEAD nor index
    assert Rugged::Submodule.lookup(@repo, 'sm_gitmodules_only')

    # lookup git repo subdir that is not added as submodule */
    assert_raises Rugged::SubmoduleError do
      Rugged::Submodule.lookup(@repo, 'not-submodule')
    end

    # lookup existing directory that is not a submodule
    assert_nil Rugged::Submodule.lookup(@repo, 'just_a_dir')

    # lookup existing file that is not a submodule
    assert_nil Rugged::Submodule.lookup(@repo, 'just_a_file')

    # lookup non-existent item
    assert_nil Rugged::Submodule.lookup(@repo, 'no_such_file')
  end

  def test_submodule_attribute_getters
    submodule = Rugged::Submodule.lookup(@repo, 'sm_unchanged')
    oid = "480095882d281ed676fe5b863569520e54a7d5c0"

    submodule_repo = submodule.repository
    assert_instance_of Rugged::Repository, submodule_repo

    assert :none, submodule.ignore
    assert submodule.path.end_with?('sm_unchanged')
    assert submodule.url.end_with?('submod2_target')
    assert_equal 'sm_unchanged', submodule.name

    assert_equal oid, submodule.head_oid
    assert_equal oid, submodule.index_oid
    assert_equal oid, submodule.workdir_oid

    submodule = Rugged::Submodule.lookup(@repo, 'sm_changed_head')
    assert_equal 'sm_changed_head', submodule.name
    assert_equal oid, submodule.head_oid
    assert_equal oid, submodule.index_oid
		assert_equal '3d9386c507f6b093471a3e324085657a3c2b4247', submodule.workdir_oid

    submodule = Rugged::Submodule.lookup(@repo, 'sm_added_and_uncommited')
    assert_equal 'sm_added_and_uncommited', submodule.name
    assert_nil submodule.head_oid
    assert_equal oid, submodule.index_oid
    assert_equal oid, submodule.workdir_oid

    submodule = Rugged::Submodule.lookup(@repo, 'sm_missing_commits')
    assert_equal 'sm_missing_commits', submodule.name
    assert_equal oid, submodule.head_oid
    assert_equal oid, submodule.index_oid
		assert_equal '5e4963595a9774b90524d35a807169049de8ccad', submodule.workdir_oid
  end

  def test_submodule_status_unchanged
    submodule = Rugged::Submodule.lookup(@repo, 'sm_unchanged')
    expected = [:in_head, :in_index, :in_config, :in_workdir]
    assert_equal expected, submodule.status
    assert submodule.in_head?
    assert submodule.in_index?
    assert submodule.in_config?
    assert submodule.in_workdir?
    assert submodule.unmodified?
    refute submodule.dirty_workdir?
  end

  def test_submodule_each
    assert_instance_of Enumerator, Rugged::Submodule.each(@repo)
    assert_instance_of Enumerator, @repo.submodules

    Rugged::Submodule.each(@repo) do |submodule|
      assert_equal :none, submodule.ignore
      assert submodule.name
      assert submodule.url
      assert submodule.path
    end

    # test error handling in callback
    assert_raises TestException do
      Rugged::Submodule.each(@repo) do |submodule|
        raise TestException
      end
    end
  end

  def test_submodule_status_ignore_none
    submodule = Rugged::Submodule.lookup(@repo, 'sm_changed_index')
    assert_includes submodule.status, :dirty_workdir_index
    assert submodule.dirty_workdir_index?

    submodule = Rugged::Submodule.lookup(@repo, 'sm_changed_head')
    assert_includes submodule.status, :modified_in_workdir
    assert submodule.modified_in_workdir?

    submodule = Rugged::Submodule.lookup(@repo, 'sm_changed_file')
    assert_includes submodule.status, :modified_files_in_workdir
    assert submodule.modified_files_in_workdir?
    assert submodule.dirty_workdir?
    refute submodule.unmodified?

    submodule = Rugged::Submodule.lookup(@repo, 'sm_changed_untracked_file')
    assert_includes submodule.status, :untracked_files_in_workdir
    assert submodule.untracked_files_in_workdir?

    submodule = Rugged::Submodule.lookup(@repo, 'sm_missing_commits')
    assert_includes submodule.status, :modified_in_workdir
    assert submodule.modified_in_workdir?

    submodule = Rugged::Submodule.lookup(@repo, 'sm_added_and_uncommited')
    assert_includes submodule.status, :added_to_index
    assert submodule.added_to_index?

    sm_unchanged_path = File.join(@repo.workdir, 'sm_unchanged')

    # removed sm_unchanged for deleted workdir
    FileUtils.remove_entry_secure(sm_unchanged_path)
    submodule = Rugged::Submodule.lookup(@repo, 'sm_unchanged')
    assert_includes submodule.status, :deleted_from_workdir
    assert submodule.deleted_from_workdir?

    # now mkdir sm_unchanged to test uninitialized
    FileUtils.mkdir(sm_unchanged_path, :mode => 0755)
    submodule = Rugged::Submodule.lookup(@repo, 'sm_unchanged')
    submodule.reload
    assert_includes submodule.status, :uninitialized
    assert submodule.uninitialized?

    # update sm_changed_head in index
    submodule = Rugged::Submodule.lookup(@repo, 'sm_changed_head')
    submodule.add_to_index
    assert_includes submodule.status, :modified_in_index
    assert submodule.modified_in_index?

    # remove sm_changed_head from index */
    index = @repo.index
    index.remove('sm_changed_head')
    index.write

    submodule = Rugged::Submodule.lookup(@repo, 'sm_changed_head')
    submodule.reload
    assert_includes submodule.status, :deleted_from_index
    assert submodule.deleted_from_index?
  end

  def test_submodule_ignore
    sm_unchanged_path = File.join(@repo.workdir, 'sm_unchanged')
    # removed sm_unchanged for deleted workdir
    FileUtils.remove_entry_secure(sm_unchanged_path)

    # untracked
    submodule = Rugged::Submodule.lookup(@repo, 'sm_changed_untracked_file')

    submodule.ignore = :untracked

    assert submodule.unmodified?
    refute submodule.untracked_files_in_workdir?

    submodule.reset_ignore

    refute submodule.unmodified?
    assert submodule.untracked_files_in_workdir?

    #dirty
    submodule = Rugged::Submodule.lookup(@repo, 'sm_changed_file')
    submodule.ignore = :dirty

    refute submodule.modified_files_in_workdir?

    submodule.reset_ignore

    assert submodule.modified_files_in_workdir?

    #all
    submodule = Rugged::Submodule.lookup(@repo, 'sm_added_and_uncommited')
    submodule.ignore = :all

    assert submodule.unmodified?
    refute submodule.added_to_index?

    submodule.reset_ignore

    assert submodule.added_to_index?
    refute submodule.unmodified?
  end

  def test_submodule_modify
    url = 'https://github.com/libgit2/libgit2.git'
    submodule = Rugged::Submodule.lookup(@repo, 'sm_changed_head')

    submodule.ignore = :untracked
    submodule.url = url

    submodule.save
    submodule.reload

    assert_equal :untracked, submodule.ignore
    assert_equal url, submodule.url
  end

  def test_submodule_update
    submodule = Rugged::Submodule.lookup(@repo, 'sm_unchanged')
    assert_equal :checkout, submodule.update

    submodule.update = :rebase
    assert_equal :rebase, submodule.update

    submodule.update = :merge
    assert_equal :merge, submodule.update

    submodule.update = :none
    assert_equal :none, submodule.update

    # reset
    submodule.reset_update
    assert_equal :checkout, submodule.update
  end

  def test_submodule_sync
    submodule = Rugged::Submodule.lookup(@repo, 'sm_unchanged')

	 # At this point, the .git/config URLs for the submodules have
	 # not be rewritten with the absolute paths (although the
	 # .gitmodules have.  Let's confirm that they DO NOT match
	 # yet, then we can do a sync to make them match...
   refute_equal submodule.url, @repo.config['submodule.sm_unchanged.url']

   submodule.sync

   assert_equal submodule.url, @repo.config['submodule.sm_unchanged.url']
  end

  def test_submodule_init
    submodule = Rugged::Submodule.lookup(@repo, 'sm_unchanged')

    #erase submodule data from .git/config
    @repo.config.delete('submodule.sm_unchanged.url')

    # confirm no submodule data in config
    assert_nil @repo.config['submodule.sm_unchanged.url']

    # call init and see that settings are copied. Call it twice, just to check
    # if it accepts the overwrite flag and that it's optional
    submodule.init(:overwrite)
    submodule.init

    submodule.reload

	  # confirm submodule data in config
    assert_equal submodule.url, @repo.config['submodule.sm_unchanged.url']
  end

  def test_submodule_setup_add
    url = 'https://github.com/libgit2/libgit2.git'
    submod_path = 'sm_libgit2'
    second_submod_path = 'sm2_libgit2'

    # re-add existing submodule
    assert_raises Rugged::SubmoduleError do
      Rugged::Submodule.setup_add(@repo, 'whatever', 'sm_unchanged', :gitlink)
    end

    # add a submodule using gitlink
    submodule = Rugged::Submodule.setup_add(@repo, url, submod_path, :gitlink)

    assert File.file?(File.join(@repo.workdir, submod_path, '.git'))
    assert File.directory?(File.join(@repo.path, 'modules'))
    assert File.directory?(File.join(@repo.path, 'modules', submod_path))
    assert File.file?(File.join(@repo.path, 'modules', submod_path, 'HEAD'))

    assert_equal url, @repo.config["submodule.#{submod_path}.url"]

    submodule = Rugged::Submodule.setup_add(@repo, url, second_submod_path)

    assert File.directory?(File.join(@repo.workdir, second_submod_path, '.git'))
    refute File.exists?(File.join(@repo.path, 'modules', second_submod_path))
    assert_equal url, @repo.config["submodule.#{submod_path}.url"]
  end

  def test_submodule_add
    url = File.join(Rugged::TestCase::TEST_DIR, 'fixtures', 'testrepo.git')

    submodule = Rugged::Submodule.setup_add(@repo, url, 'sm_testrepo', :gitlink)
    submodule_repo = submodule.repository
    submodule_repo.remotes.first.connect(:fetch) do |remote|
      remote.download
      remote.update_tips!
    end

    submodule_repo.reset('origin/master', :hard)

    submodule.finalize_add

    submodule_repo.close
  end
end
