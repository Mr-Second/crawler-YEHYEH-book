require 'json'
require 'crawler_rocks'
require 'pry'

require 'thread'
require 'thwait'

require 'book_toolkit'

require 'iconv'

class YehyehBookCrawler
  include CrawlerRocks::DSL

  def initialize update_progress: nil, after_each: nil
    @update_progress_proc = update_progress
    @after_each_proc = after_each

    @index_url = "http://www.yehyeh.com.tw/books.aspx"
    @ic = Iconv.new("utf-8//translit//IGNORE","utf-8")
    # ?a=000247&pgenow=0&sysmainid=books&titleid=&edtitleid=?&mode=dblist&edpagenow=94
  end

  def books
    @books = []
    @threads = []

    visit @index_url

    page_num = @doc.css('#ctl00_ContentPlaceHolder1_MSTableCellbooks72').text.gsub(/[^\d]/, '').to_i
    # (1..10).each do |i|
    (1..page_num).each do |i|
      sleep(1) until (
        @threads.delete_if { |t| !t.status };  # remove dead (ended) threads
        @threads.count < (ENV['MAX_THREADS'] || 5)
      )
      @threads << Thread.new do

        r = RestClient.get(
          @index_url +
          "?a=000247&pgenow=0&sysmainid=books&titleid=&edtitleid=?&mode=dblist&edpagenow=#{i}"
        )
        doc = Nokogiri::HTML(@ic.iconv r)

        doc.css('.dbimg_list').each do |grid|
          name = grid.css('.dbimg_list_title').text
          url = grid.css('.dbimg_list_title a').empty? ? nil : URI.join(@index_url, grid.css('.dbimg_list_title a')[0][:href]).to_s
          rows = grid.css('table table tr')
          author = rows[0].css('td')[1].text.gsub(/\u{a0}$/, '')
          isbn = rows[1].css('td')[1].text.gsub(/\u{a0}$/, '')
          internal_code = rows[2].css('td')[1].text.gsub(/\u{a0}$/, '')

          original_price = rows[3].css('td')[1].text.gsub(/[^\d]/, '').to_i
          original_price = nil if original_price == 0

          external_image_url = grid.css('img').empty? ? nil : URI.join(@index_url, URI.encode(grid.css('img')[0][:src])).to_s

          invalid_isbn = nil
          begin
            isbn = BookToolkit.to_isbn13(isbn)
          rescue Exception => e
            invalid_isbn = isbn
            isbn = nil
          end

          book = {
            name: name,
            url: url,
            author: author,
            isbn: isbn,
            invalid_isbn: invalid_isbn,
            author: author,
            internal_code: internal_code,
            original_price: original_price,
            external_image_url: external_image_url,
            known_supplier: 'yehyeh'
          }

          @after_each_proc.call(book: book) if @after_each_proc

          @books << book
        end
        print "#{i} / #{page_num}\n"
      end # end thread
    end # end each page

    ThreadsWait.all_waits(*@threads)
    @books
  end
end

# cc = YehyehBookCrawler.new
# File.write('yehyeh_books.json', JSON.pretty_generate(cc.books))
