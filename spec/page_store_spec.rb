$:.unshift(File.dirname(__FILE__))
require 'spec_helper'

module Medusa
  describe PageStore do

    before(:all) do
      FakeWeb.clean_registry
    end

    shared_examples_for "page storage" do
      it "should be able to compute single-source shortest paths in-place" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '3'])
        pages << FakePage.new('1', :redirect => '2')
        pages << FakePage.new('2', :links => ['4'])
        pages << FakePage.new('3')
        pages << FakePage.new('4')

        # crawl, then set depths to nil
        page_store = Medusa.crawl(pages.first.url, @opts) do |a|
          a.after_crawl do |ps|
            (0..4).to_a.each { |i| ps[SPEC_DOMAIN + i.to_s].depth = nil }
          end
        end.pages

        page_store.should respond_to(:shortest_paths!)

        page_store.shortest_paths!(pages[0].url)
        page_store[pages[0].url].depth.should == 0
        page_store[pages[1].url].depth.should == 1
        page_store[pages[2].url].depth.should == 1
        page_store[pages[3].url].depth.should == 1
        page_store[pages[4].url].depth.should == 2
      end
    end

    describe Hash do
      it_should_behave_like "page storage"

      before(:all) do
        @opts = {}
      end
    end
  end
end
