
#-- This code makes some assumptions.
# -- SSRN URLs follow the templates described by the constants defined below
# -- There is no paging of the list of papers displayed by an author page -- that is, all of an author's papers are
#    listed on a single page, no matter how many there are.


CLS_TRIPLE_FILE=''
SSRN_AUTHOR_PREFIX='http://papers.ssrn.com/sol3/cf_dev/AbsByAuth.cfm?per_id='
SSRN_ABSTRACT_PREFIX='http://papers.ssrn.com/sol3/papers.cfm?abstract_id='
GOOGLE_UID='access.lii.cornell@gmail.com'
GOOGLE_PWD='crankmaster'
GOOGLE_SPREADSHEET_KEY='0AkDG2tEbluFPdFhIT09tdnpKWHV2dHRNQUVMLXBNSHc'
CITATIONER_URI='http://mojo.law.cornell.edu/services/citationer/'

require 'rubygems'
require 'net/http'
require 'simple-tidy'
require 'nokogiri'
require 'chronic'
require 'google_drive'
require 'tempfile'

#-- class for representing/modeling SSRN abstract pages

class SSRNAbstractPage
  attr_reader :paper_id,:author_id,:url,:keywords,:jelcodes,:coauthors,:abstract,:online_date,:pub_date,:doi,:title,:paper_url

  def initialize(my_id, my_author_id)
    @paper_id = my_id
    @author_id = my_author_id
    @url = SSRN_ABSTRACT_PREFIX + my_id

    @keywords = Array.new()
    @jelcodes = Array.new()
    @coauthors = Array.new()
    @abstract = nil
    @online_date = nil
    @pub_date = nil
    @doi = nil
    @title = nil
    @paper_url = nil
    @abstract_views = nil
    @paper_dls = nil
    @paper_citations = nil
    @paper_footnotes = nil
    @dl_rank = nil

    begin
      uri = URI(@url)
      html = Net::HTTP.get(uri)
      unless html
        raise "Abstract page #{@url} unavailable"
      end
    rescue Exception => e
      puts e.message
      puts e.backtrace.inspect
    end
    # SSRN throws javascript in *before* the DOCTYPE declaration, believe it or not.  we don't need it, so...
    html.sub!(/^.*<!DOCTYPE/m,'<!DOCTYPE')
    # also, too, bogus <nobr> tags
    html.gsub!(/<\/*nobr>/m, '')

    clean_html = SimpleTidy.clean(html, :force_output => true)
    @doc = Nokogiri::HTML(clean_html)
  end

  #-- scrape the contents of the page
  def scrape
    scrape_metas
    scrape_stats
    scrape_authors
    scrape_abstract
    scrape_jelcodes
  end

  #-- get interesting metatag content
  def scrape_metas
      @title = @doc.at_xpath("//meta[@name='citation_title']")["content"]
      @online_date = @doc.at_xpath("//meta[@name='citation_online_date']")["content"]
      @pub_date = @doc.at_xpath("//meta[@name='citation_publication_date']")["content"]
      @doi = @doc.at_xpath("//meta[@name='citation_doi']")["content"]
      @paper_url =@doc.at_xpath("//meta[@name='citation_pdf_url']")["content"]
      @keywords = @doc.at_xpath("//meta[@name='citation_keywords']")["content"].split(/,\s*/)
  end

  #-- get paper statistics
  def scrape_stats
    @labels = Array.new
    @stats = Array.new
    @doc.css("span.statisticsText").each do |label|
      @labels.push(label.inner_text())
    end
    idx = 0
    @doc.css("span.statNumber").each do |stat|
      num = stat.inner_text().gsub!(/[^0-9]/,'').to_i
      @abstract_views = num if @labels[idx] =~ /Views/
      @paper_dls = num if @labels[idx] =~ /Downloads/
      @paper_citations = num if @labels[idx] =~ /Citations/
      @paper_footnotes = num if @labels[idx] =~ /Footnotes/
      @dl_rank = num if @labels[idx] =~ /Rank/
      idx = idx+1
    end
  end

  #-- get SSRN IDs of coauthors
  def scrape_authors
    @doc.xpath("//center/font/a[@title='View other papers by this author']").each do |link|
      auth_id =  /per_id=([0-9]+)/.match(link['href'])[1]
       @coauthors.push(auth_id) unless auth_id == @author_id
    end
  end

  def scrape_abstract
      @abstract = @doc.at_xpath("//div/div/div/font").inner_text()
  end

  def scrape_jelcodes
    @doc.xpath("//div/div/div/p/font").each do |chunk|
      stuff = /JEL\s*Classification:\s*((([A-Z][0-9]+),*\s*)+)/.match(chunk.inner_text())
      if stuff
        @jelcodes = stuff[1].split(/,\s*/)
      end
    end
  end

  def create_triples
  end


#-- override to_s, mostly for debugging purposes
  def to_s
    strang = <<-"eos"
Title: #{@title}
Online date: #{@online_date}
Publication date: #{@pub_date}
DOI: #{@doi}
PDF URL: #{@paper_url}

Abstract: #{@abstract}

Keywords: #{@keywords.join("\n")}
JEL classification: #{@jelcodes.join("\n")}
Coauthors (SSRN): #{@coauthors.join("\n")}
Abstract views: #{@abstract_views}
Downloads: #{@paper_dls}
Citations: #{@paper_citations}
Footnotes: #{@paper_footnotes}
Download rank: #{@dl_rank}
    eos
  end
end

class SSRNPaper
  def initialize(paper_url)
    # could be HTML, PDF, pretty much anything
    @stuff = Net::HTTP.get(URI(paper_url))
  end
  def extract_citations
    postfile = Tempfile.new('clsauthor')
    postfile.write(html)
    postfile.close


  end
  def create_triples

  end
end

#-- class for modeling/constructing SSRN author pages

class SSRNAuthorPage
  attr_reader :ssrn_id, :paperlist
  def initialize(my_ssrn_id)
    @ssrn_id = my_ssrn_id
    @abstractlist = Array.new()
    begin
      html = Net::HTTP.get(URI(SSRN_AUTHOR_PREFIX+@ssrn_id))
      raise "Author listing page for ID #{@ssrn_id} unavailable" unless html
    rescue Exception => e
      puts e.message
      puts e.backtrace.inspect
    end
    # SSRN throws javascript in at the top, just as it does on the Abstract pages, but this time there's not even a
    # DOCTYPE declaration. *sigh*
    html.sub!(/^.*<html/m,'<html')
    # also, too, bogus <nobr> tags
    html.gsub!(/<\/*nobr>/m, '')
    clean_html = SimpleTidy.clean(html, :force_output => true)
    @doc = Nokogiri::HTML(clean_html)
  end

  #-- gather the list of abstract ids for each author
  def scrape
    @doc.xpath("//a[@class='textlink']").each do |link|
      stuff = /http:\/\/ssrn\.com\/abstract=([0-9]+)/.match(link['href'])
      @abstractlist.push stuff[1] if stuff
    end
  end

  def process_abstracts
    @abstractlist.each do |absnum|
      abstract =  SSRNAbstractPage.new(absnum, @ssrn_id)
      abstract.scrape
      abstract.create_triples
    end
  end

  def to_s
    strang = <<-"eos"
     #{@abstractlist.join("\n")}
  eos
  end
end


class CLSAuthorEndpoint
  def initialize(my_url)
  end
end

#-- processes the configuration spreadsheet
class CLSAuthorSpreadsheet
  def initialize

  end
  def create_triples

  end
end


# pseudocode
# check to see if we're printing out triples or updating the endpoint
# get a list of author objects from the spreadsheet
# emit the author triples however
# for each author, get the papers
# emit the paper triples however

# page/paperlist test
#pg = SSRNAuthorPage.new('45120')
#pg.scrape
#puts "#{pg}"

# abstract page test
pg = SSRNAbstractPage.new('2218855','489995')
pg.scrape
puts "#{pg}"