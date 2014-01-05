module Jekyll

  class TocTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
    end

    def render(context)
      toc = '<ul>'
      context.registers[:site].pages.each do |page|
        toc += "<li><a href=\"#{page.url}\">#{page.data['title']}</a>\
<div>#{page.path}</div></li>"
      end
      toc += '</ul>'
    end

  end

end

Liquid::Template.register_tag('toc', Jekyll::TocTag)
