require 'spec_helper'

describe WorkSearchForm do
  describe "searching" do
    let!(:collection) do
      FactoryBot.create(:collection, id: 1)
    end

    let!(:work) do
      FactoryBot.create(:work,
                         title: "There and back again",
                         authors: [Pseud.find_by(name: "JRR Tolkien") || FactoryBot.create(:pseud, name: "JRR Tolkien")],
                         summary: "An unexpected journey",
                         fandom_string: "The Hobbit",
                         character_string: "Bilbo Baggins",
                         posted: true,
                         expected_number_of_chapters: 3,
                         complete: false,
                         language_id: 1)
    end

    let!(:second_work) do
      FactoryBot.create(:work,
                         title: "Harry Potter and the Sorcerer's Stone",
                         authors: [Pseud.find_by(name: "JK Rowling") || FactoryBot.create(:pseud, name: "JK Rowling")],
                         summary: "Mr and Mrs Dursley, of number four Privet Drive...",
                         fandom_string: "Harry Potter",
                         character_string: "Harry Potter, Ron Weasley, Hermione Granger",
                         posted: true,
                         language_id: 2)
    end

    before(:each) do
      # This doesn't work properly in the factory.
      second_work.collection_ids = [collection.id]
      second_work.save

      work.stat_counter.update_attributes(kudos_count: 1200, comments_count: 120, bookmarks_count: 12)
      second_work.stat_counter.update_attributes(kudos_count: 999, comments_count: 99, bookmarks_count: 9)
      run_all_indexing_jobs
    end

    it "finds works that match" do
      results = WorkSearchForm.new(query: "Hobbit").search_results
      expect(results).to include work
      expect(results).not_to include second_work
    end

    it "finds works with tags having numbers" do
      work.freeform_string = "Episode: s01e01,Season/Series 01,Brooklyn 99"
      work.save

      second_work.freeform_string = "Episode: s02e01,Season/Series 99"
      second_work.save

      run_all_indexing_jobs

      # The colon is a reserved character we cannot automatically escape
      # without breaking all the hidden search operators.
      # We just have to quote it.
      results = WorkSearchForm.new(query: "\"Episode: s01e01\"").search_results
      expect(results).to include work
      expect(results).not_to include second_work

      # Quote the search term since it has a space.
      results = WorkSearchForm.new(query: "\"Season/Series 99\"").search_results
      expect(results).not_to include work
      expect(results).to include second_work
    end

    describe "when searching unposted works" do
      before(:each) do
        work.update_attribute(:posted, false)
        run_all_indexing_jobs
      end

      it "should not return them by default" do
        work_search = WorkSearchForm.new(query: "Hobbit")
        expect(work_search.search_results).not_to include work
      end
    end

    describe "when searching restricted works" do
      before(:each) do
        work.update_attribute(:restricted, true)
        run_all_indexing_jobs
      end

      it "should not return them by default" do
        work_search = WorkSearchForm.new(query: "Hobbit")
        expect(work_search.search_results).not_to include work
      end

      it "should return them when asked" do
        work_search = WorkSearchForm.new(query: "Hobbit", show_restricted: true)
        expect(work_search.search_results).to include work
      end
    end

    describe "when searching incomplete works" do
      it "should not return them when asked for complete works" do
        work_search = WorkSearchForm.new(query: "Hobbit", complete: true)
        expect(work_search.search_results).not_to include work
      end
    end

    describe "when searching by title" do
      it "should match partial titles" do
        work_search = WorkSearchForm.new(title: "back again")
        expect(work_search.search_results).to include work
      end

      it "should not match fields other than titles" do
        work_search = WorkSearchForm.new(title: "Privet Drive")
        expect(work_search.search_results).not_to include second_work
      end
    end

    describe "when searching by author" do
      it "should match partial author names" do
        work_search = WorkSearchForm.new(creators: "Rowling")
        expect(work_search.search_results).to include second_work
      end

      it "should not match fields other than authors" do
        work_search = WorkSearchForm.new(creators: "Baggins")
        expect(work_search.search_results).not_to include work
      end

      it "should turn - into NOT" do
        work_search = WorkSearchForm.new(creators: "-Tolkien")
        expect(work_search.search_results).not_to include work
      end
    end

    describe "when searching by language" do
      it "should only return works in that language" do
        work_search = WorkSearchForm.new(language_id: 1)
        expect(work_search.search_results).to include work
        expect(work_search.search_results).not_to include second_work
      end
    end

    describe "when searching by fandom" do
      it "should only return works in that fandom" do
        work_search = WorkSearchForm.new(fandom_names: "Harry Potter")
        expect(work_search.search_results).not_to include work
        expect(work_search.search_results).to include second_work
      end

      it "should not choke on exclamation points" do
        work_search = WorkSearchForm.new(fandom_names: "Potter!")
        expect(work_search.search_results).to include second_work
        expect(work_search.search_results).not_to include work
      end
    end

    describe "when searching by collection" do
      it "should only return works in that collection" do
        work_search = WorkSearchForm.new(collection_ids: [1])
        expect(work_search.search_results).to include second_work
        expect(work_search.search_results).not_to include work
      end
    end

    describe "when searching by series title" do
      let!(:main_series) { create(:series, title: "Persona: Dancing in Starlight", works: [work]) }
      let!(:spinoff_series) { create(:series, title: "Persona 5", works: [second_work]) }
      let!(:standalone_work) { create(:work) }

      context "using the \"series_titles\" field" do
        before { run_all_indexing_jobs }

        it "returns only works in matching series" do
          results = WorkSearchForm.new(series_titles: "dancing").search_results
          expect(results).to include(work)
          expect(results).not_to include(second_work, standalone_work)
        end

        it "returns only works in matching series with numbers in titles" do
          results = WorkSearchForm.new(series_titles: "persona 5").search_results
          expect(results).to include(second_work)
          expect(results).not_to include(work, standalone_work)
        end

        it "returns all works in series for wildcard queries" do
          results = WorkSearchForm.new(series_titles: "*").search_results
          expect(results).to include(work, second_work)
          expect(results).not_to include(standalone_work)
        end
      end

      context "using the \"query\" field" do
        before { run_all_indexing_jobs }

        it "returns only works in matching series" do
          results = WorkSearchForm.new(query: "series_titles: dancing").search_results
          expect(results).to include(work)
          expect(results).not_to include(second_work, standalone_work)
        end

        it "returns only works in matching series with numbers in titles" do
          results = WorkSearchForm.new(query: "series_titles: \"persona 5\"").search_results
          expect(results).to include(second_work)
          expect(results).not_to include(work, standalone_work)
        end

        it "returns all works in series for wildcard queries" do
          results = WorkSearchForm.new(query: "series_titles: *").search_results
          expect(results).to include(work, second_work)
          expect(results).not_to include(standalone_work)
        end
      end

      context "after a series is renamed" do
        before do
          main_series.update!(title: "Megami Tensei")
          run_all_indexing_jobs
        end

        it "returns only works in matching series" do
          results = WorkSearchForm.new(series_titles: "megami").search_results
          expect(results).to include(work)
          expect(results).not_to include(second_work, standalone_work)
        end
      end

      context "after a work is removed from a series" do
        before do
          work.serial_works.first.destroy!
          run_all_indexing_jobs
        end

        it "returns only works in matching series" do
          results = WorkSearchForm.new(series_titles: "persona").search_results
          expect(results).to include(second_work)
          expect(results).not_to include(work, standalone_work)
        end
      end

      context "after a series is deleted" do
        before do
          spinoff_series.destroy!
          run_all_indexing_jobs
        end

        it "returns only works in matching series" do
          results = WorkSearchForm.new(series_titles: "persona").search_results
          expect(results).to include(work)
          expect(results).not_to include(second_work, standalone_work)
        end
      end
    end

    describe "when searching by word count" do
      before(:each) do
        work.chapters.first.update_attributes(content: "This is a work with a word count of ten.", posted: true)
        work.save

        second_work.chapters.first.update_attributes(content: "This is a work with a word count of fifteen which is more than ten.", posted: true)
        second_work.save

        run_all_indexing_jobs
      end

      it "should find the right works less than a given number" do
        work_search = WorkSearchForm.new(word_count: "<13")

        expect(work_search.search_results).to include work
        expect(work_search.search_results).not_to include second_work
      end
      it "should find the right works more than a given number" do
        work_search = WorkSearchForm.new(word_count: "> 10")
        expect(work_search.search_results).not_to include work
        expect(work_search.search_results).to include second_work
      end

      it "should find the right works within a range" do
        work_search = WorkSearchForm.new(word_count: "0-10")
        expect(work_search.search_results).to include work
        expect(work_search.search_results).not_to include second_work
      end
    end

    describe "when searching by kudos count" do
      it "should find the right works less than a given number" do
        work_search = WorkSearchForm.new(kudos_count: "< 1,000")
        expect(work_search.search_results).to include second_work
        expect(work_search.search_results).not_to include work
      end
      it "should find the right works more than a given number" do
        work_search = WorkSearchForm.new(kudos_count: "> 999")
        expect(work_search.search_results).to include work
        expect(work_search.search_results).not_to include second_work
      end

      it "should find the right works within a range" do
        work_search = WorkSearchForm.new(kudos_count: "1,000-2,000")
        expect(work_search.search_results).to include work
        expect(work_search.search_results).not_to include second_work
      end
    end

    describe "when searching by comments count" do
      it "should find the right works less than a given number" do
        work_search = WorkSearchForm.new(comments_count: "< 100")
        expect(work_search.search_results).to include second_work
        expect(work_search.search_results).not_to include work
      end
      it "should find the right works more than a given number" do
        work_search = WorkSearchForm.new(comments_count: "> 99")
        expect(work_search.search_results).to include work
        expect(work_search.search_results).not_to include second_work
      end

      it "should find the right works within a range" do
        work_search = WorkSearchForm.new(comments_count: "100-2,000")
        expect(work_search.search_results).to include work
        expect(work_search.search_results).not_to include second_work
      end
    end

    describe "when searching by bookmarks count" do
      it "should find the right works less than a given number" do
        work_search = WorkSearchForm.new(bookmarks_count: "< 10")
        expect(work_search.search_results).to include second_work
        expect(work_search.search_results).not_to include work
      end
      it "should find the right works more than a given number" do
        work_search = WorkSearchForm.new(bookmarks_count: ">9")
        expect(work_search.search_results).to include work
        expect(work_search.search_results).not_to include second_work
      end

      it "should find the right works within a range" do
        work_search = WorkSearchForm.new(bookmarks_count: "10-20")
        expect(work_search.search_results).to include work
        expect(work_search.search_results).not_to include second_work
      end
    end
  end

  describe "searching for authors who changes username" do
    let!(:user) { create(:user, login: "81_white_chain") }
    let!(:second_pseud) { create(:pseud, name: "peacekeeper", user: user) }
    let!(:work_by_default_pseud) { create(:posted_work, authors: [user.default_pseud]) }
    let!(:work_by_second_pseud) { create(:posted_work, authors: [second_pseud]) }

    before { run_all_indexing_jobs }

    it "matches only on their current username" do
      results = WorkSearchForm.new(creators: "81_white_chain").search_results
      expect(results).to include(work_by_default_pseud)
      expect(results).to include(work_by_second_pseud)

      user.reload
      user.login = "82_white_chain"
      user.save!
      run_all_indexing_jobs

      results = WorkSearchForm.new(creators: "81_white_chain").search_results
      expect(results).to be_empty

      results = WorkSearchForm.new(creators: "82_white_chain").search_results
      expect(results).to include(work_by_default_pseud)
      expect(results).to include(work_by_second_pseud)
    end
  end

  describe "sorting results" do
    describe "by authors" do
      before do
        %w(21st_wombat 007aardvark).each do |pseud_name|
          create(:posted_work, authors: [create(:pseud, name: pseud_name)])
        end
        run_all_indexing_jobs
      end

      it "returns all works in the correct order of sortable pseud values" do
        sorted_pseuds_asc = ["007aardvark", "21st_wombat"]

        work_search = WorkSearchForm.new(sort_column: "authors_to_sort_on")
        expect(work_search.search_results.map(&:authors_to_sort_on)).to eq sorted_pseuds_asc

        work_search = WorkSearchForm.new(sort_column: "authors_to_sort_on", sort_direction: "asc")
        expect(work_search.search_results.map(&:authors_to_sort_on)).to eq sorted_pseuds_asc

        work_search = WorkSearchForm.new(sort_column: "authors_to_sort_on", sort_direction: "desc")
        expect(work_search.search_results.map(&:authors_to_sort_on)).to eq sorted_pseuds_asc.reverse
      end
    end

    describe "by authors who changes username" do
      let!(:user_1) { create(:user, login: "cioelle") }
      let!(:user_2) { create(:user, login: "ruth") }

      before do
        create(:posted_work, authors: [user_1.default_pseud])
        create(:posted_work, authors: [user_2.default_pseud])
        run_all_indexing_jobs
      end

      it "returns all works in the correct order of sortable pseud values" do
        work_search = WorkSearchForm.new(sort_column: "authors_to_sort_on")
        expect(work_search.search_results.map(&:authors_to_sort_on)).to eq ["cioelle", "ruth"]

        user_1.login = "yabalchoath"
        user_1.save!
        run_all_indexing_jobs

        work_search = WorkSearchForm.new(sort_column: "authors_to_sort_on")
        expect(work_search.search_results.map(&:authors_to_sort_on)).to eq ["ruth", "yabalchoath"]
      end
    end
  end
end
