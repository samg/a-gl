module Elastic
  module WikiRepositoriesSearch
    extend ActiveSupport::Concern

    included do
      include Elasticsearch::Git::Repository

      index_name [Rails.application.class.parent_name.downcase, Rails.env].join('-')

      def repository_id
        "wiki_#{project.id}"
      end

      def self.repositories_count
        Project.where(wiki_enabled: true).count
      end

      def client_for_indexing
        self.__elasticsearch__.client
      end

      def self.import
        Project.where(wiki_enabled: true).find_each do |project|
          unless project.wiki.empty?
            project.wiki.index_blobs
          end
        end
      end
    end
  end
end
