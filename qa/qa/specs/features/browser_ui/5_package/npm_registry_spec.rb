# frozen_string_literal: true

module QA
  RSpec.describe 'Package', :orchestrated, :packages do
    describe 'npm registry' do
      include Runtime::Fixtures

      let!(:registry_scope) { project.group.sandbox.path }
      let(:auth_token) do
        unless Page::Main::Menu.perform(&:signed_in?)
          Flow::Login.sign_in
        end

        Resource::PersonalAccessToken.fabricate!.token
      end

      let!(:project) do
        Resource::Project.fabricate_via_api! do |project|
          project.name = 'npm-registry-project'
        end
      end

      let(:package) do
        Resource::Package.new.tap do |package|
          package.name = "@#{registry_scope}/#{project.name}"
          package.project = project
        end
      end

      after do
        package.remove_via_api!
      end

      it 'publishes an npm package and then deletes it', testcase: 'https://gitlab.com/gitlab-org/quality/testcases/-/issues/944' do
        uri = URI.parse(Runtime::Scenario.gitlab_address)
        gitlab_host_with_port = "#{uri.host}:#{uri.port}"
        gitlab_address_with_port = "#{uri.scheme}://#{uri.host}:#{uri.port}"
        package_json = {
          file_path: 'package.json',
          content: <<~JSON
            {
              "name": "#{package.name}",
              "version": "1.0.0",
              "description": "Example package for GitLab npm registry",
              "publishConfig": {
                "@#{registry_scope}:registry": "#{gitlab_address_with_port}/api/v4/projects/#{project.id}/packages/npm/"
              }
            }
          JSON
        }
        npmrc = {
          file_path: '.npmrc',
          content: <<~NPMRC
            //#{gitlab_host_with_port}/api/v4/projects/#{project.id}/packages/npm/:_authToken=#{auth_token}
            //#{gitlab_host_with_port}/api/v4/packages/npm/:_authToken=#{auth_token}
            @#{registry_scope}:registry=#{gitlab_address_with_port}/api/v4/packages/npm/
          NPMRC
        }

        # Use a node docker container to publish the package
        with_fixtures([npmrc, package_json]) do |dir|
          Service::DockerRun::NodeJs.new(dir).publish!
        end

        project.visit!
        Page::Project::Menu.perform(&:click_packages_link)

        Page::Project::Packages::Index.perform do |index|
          expect(index).to have_package(package.name)

          index.click_package(package.name)
        end

        Page::Project::Packages::Show.perform do |show|
          expect(show).to have_package_info(package.name, "1.0.0")

          show.click_delete
        end

        Page::Project::Packages::Index.perform do |index|
          expect(index).to have_content("Package deleted successfully")
          expect(index).not_to have_package(package.name)
        end
      end
    end
  end
end
