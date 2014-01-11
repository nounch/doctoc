require 'pp'

module Jekyll

  # XXX: This is a workaround necessary to prevent Jekyll from eagerly
  # cleaning up new `IndexPage' files after they have been written to
  # `site'.
  #
  # This is a known Jekyll bug (#268):
  #   https://github.com/jekyll/jekyll/issues/268
  class Site
    def process
      self.reset
      self.read
      self.cleanup
      self.generate
      self.render
      self.write
    end
  end

  #########################################################################
  # TOC Plugin
  #########################################################################

  module Toc


    #======================================================================
    # Path Tree
    #======================================================================

    class TreeNode
      attr_accessor :name, :data, :children, :html_string

      def initialize(name, data, children = [])
        @name = name
        @data = data
        @children = children

        @pp_indentation_width = 2
        @html_string = []
      end

      def pp(counter, string)
        string << ' ' * (counter * @pp_indentation_width) +
          File.basename(@name) + "\n"
        counter += 1

        @children.each do |child|
          child.pp counter, string
        end

        counter -= 1
      end

      def html(children_only=false)
        children_empty_states = @children.collect { |c| c.children.empty? }
        is_flat = !children_empty_states.select { |c| c == true}.empty?

        html = []
        if !@children.empty? && is_flat
          # Completely flat lists
          html << '<ul>'
          @children.each do |c|
            html <<
              "<li><a href=\"#{c.name}\">#{File.basename c.name}</a></li>"
          end
          html << '</ul>'
          html.join("\n")
        else
          # Arbitrarily deeply nested lists
          if children_only
            @children.each { |child| html << child.htmlize([]) }
            html.join("\n")
          else
            self.htmlize([]).join("\n")
          end
        end
      end

      def htmlize(html, previous_children_empty=nil)
        # Leaf nodes should not be lists themselves
        if !@children.empty?
          html << '<ul>'
        end

        if previous_children_empty != true && @children.empty? &&
            Tree.current_children_empty != true
          html << '<ul>'
        end

        html << "<li><a href=\"#{@name}\">#{File.basename @name}</a></li>"

        # Semi-global state!
        #
        # The semi-global state (storing something on the `Tree' class) is
        # necessary since `@children.empty?' within the `@children.each''s
        # block would not work since it could not access the outer scope
        # correctly.
        Tree.current_children_empty = @children.empty?

        @children.each do |child|
          child.htmlize html, Tree.current_children_empty
        end

        # Leaf nodes should not be lists themselves
        if !@children.empty?
          html << '</ul>'
        end

        if previous_children_empty != true && !@children.empty? &&
            !Tree.current_children_empty != true
          html << '</ul>'
        end

        html
      end

    end


    class Tree
      attr_accessor :root

      def initialize(root)
        @root = root
        @last_found_node = nil  # Semi-global state!
        # Note: Do not use the following variable anywhere else than in
        # `TreeNode::htmlize' since it is essentially semi-global state.
        # If you rebell still do it, at least update this comment!
        @current_children_empty  # Semi-global state!
      end

      def Tree::current_children_empty
        @current_children_empty
      end

      def Tree::current_children_empty=(value)
        @current_children_empty = value
      end

      def find(node_name, node, is_node=false)
        # Special case: the searched node is one of the children of the
        # root note.
        if is_node
          if node.children.collect { |c| c.name }.include? node_name
            @last_found_node = node.children[0]
          end
        end

        node.children.each do |child|
          children = child.children.select { |n| n.name == node_name }

          if (!children.collect { |n| n.name }.include? node_name)
            self.find node_name, child
          else
            @last_found_node = children[0]  # Semi-global state!
          end

        end
        return @last_found_node
      end

      def find_parent(node_name, node=@root, parent_node=nil)
        node.children.each do |child|
          if !(child.name == node_name)
            self.find_parent(node_name, child, child)
          else
            @last_found_node = parent_node
          end
        end
        return @last_found_node
      end

      def insert_child(node_name, new_node, node=@root)
        node.children.each do |child|
          if child.name == node_name
            child.children << new_node
          else
            self.insert_child node_name, new_node, child
          end

        end
      end

      def insert_pathes(pathes)
        pathes.each_pair do |key, value|
          value.each_pair do |k, v|
            if File.basename(k) != 'index.html'
              self.insert_child(key, TreeNode.new(k, ['data']))
            end
          end

          self.insert_pathes value
        end
      end

      def pp
        counter = 0
        string = []
        @root.pp counter, string
        string.join
      end

      def html
        @root.htmlize @root.html_string
        @root.html_string.join "\n"
      end

    end


    #======================================================================
    # Actual Plugin
    #======================================================================

    class IndexPage < Page
      def initialize(site, base, dir, name, data, top_level_dir_name)
        @site = site
        @base = base
        @dir = dir
        @name = name

        self.process(@name)
        self.read_yaml(File.join(base,
                                 File.join(top_level_dir_name,
                                           '_fallback')), 'index.html')
        data.each_pair { |key, value| self.data[key] = value }
      end

    end


    class Generator < Jekyll::Generator
      priority :low

      def initialize(arg)
        super
        @tree = {}
        @nested_list = ''
        @top_level_dir_name = '/pages'
        @prev_next_list = []
      end

      def generate_index_pages(site, pathes, path_tree, toc)
        pathes.each_pair do |key, value|
          value.each_pair do |k, v|
            referrer_path = path_tree.find_parent(k).name
            if File.basename(k) != 'index.html'
              if !File.file?(File.join(site.source,
                                       File.join(k, 'index.html')))
                index_page =
                  IndexPage.new(site, site.source,
                                '/',
                                'index.html', {
                                  'referrer' => referrer_path,
                                  'referrer_name' =>
                                  File.basename(referrer_path),
                                  'doctoc' => toc,
                                  'path' =>
                                  File.join(path_tree.find(k, path_tree.root).name.gsub(/^\//, ''),
                                            'index.html'),
                                  'current_node' => File.basename(k),
                                  'doctoc_prev_next_list' =>
                                  @prev_next_list
                                },
                                @top_level_dir_name)

                index_page.render(site.layouts, site.site_payload)
                # index_page.write(site.dest)
                index_page.write(File.join(site.dest, k))
                site.pages << index_page

                # This may become a future feature.
                #
                # Generate actual source files in `pages'; required rerun
                # of Jekyll afterwards to force it to actually compile
                # those source files into `_site'.`
                # File.open(File.join(site.source,
                #                     File.join('',
                #                               File.join(k, 'index.html'))),
                #           'w') do |f|
                #   f.write '<p>Automatically generated page</p>'
                # end
              end
            end
          end

          self.generate_index_pages(site, value, path_tree, toc)
        end
      end

      def generate_prev_next_list(pathes)
        pathes.each_pair do |key, value|
          @prev_next_list << key if File.basename(key) != 'index.html'
          self.generate_prev_next_list value
        end
      end

      def generate_tree(pathes)
        pathes.each do |path|
          current = @tree
          counter = 0

          path.split("/").inject("") do |sub_path, dir|
            sub_path = File.join(sub_path, dir)

            if (current[sub_path] == nil || current[sub_path] == false) &&
                sub_path != 'index.html'
              current[sub_path] = { }
            end

            current = current[sub_path]

            sub_path
          end
        end
      end

      def generate(site)
        page_pathes = site.pages.each.collect { |page| page.path }

        generate_tree(page_pathes)

        path_tree =
          Tree.new(TreeNode.new('root', ['data'],
                                [TreeNode.new(@top_level_dir_name,
                                              ['data'])]))

        path_tree.insert_pathes({@top_level_dir_name =>
                                  @tree[@top_level_dir_name] })

        # TOC for the whole site

        toc = ''
        # Exclude the top level node since displaying `root' on the site
        # by default makes no sense. If necessary, this can still be
        # achieved by the user by wrapping the Liquid TOC tag in a HTML
        # list tag.
        path_tree.find(@top_level_dir_name,
                       path_tree.root, true).children.each do |child|
          toc += child.html
        end

        # Generate `previous'/`next' link references
        self.generate_prev_next_list @tree
        @prev_next_list = @prev_next_list[1..-1]

        # Add shared data to each page
        site.pages.each do |page|
          page.data['doctoc'] = toc
          page.data['doctoc_prev_next_list'] = @prev_next_list
        end

        # Attach the TOC to the site object so that it can be used
        # elsewhere
        site.data[:toc_tree] = path_tree

        # Generate the index pages
        self.generate_index_pages site, @tree, path_tree, toc
      end
    end

  end


  #########################################################################
  # `doctoc' Tag
  #########################################################################

  class DocTocTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
      # Special marker for parent links
      @parent_node_marker = 'parent-node'
    end

    def render(context)
      #--------------------------------------------------------------------
      # Info
      #--------------------------------------------------------------------
      #
      # The list of pages is available like this:
      #  context.registers[:site].pages
      # Anyone making a Jekyll plugin should know that.

      html = ''
      toc_tree = context.registers[:site].data[:toc_tree]
      toc = toc_tree.find('/' +
                          File.dirname(context.registers[:page]['path']),
                          toc_tree.root, true)

      # In case there is no TOC node found or the TOC node that has been
      # found is a leaf node there should not be any HTML emitted.
      if toc == nil || toc.children.empty?
        html = ''
        if !@text.empty?

          # Link to the parent node when on a leaf node page
          if @text =~ / *#{Regexp.quote(@parent_node_marker)} */
            path = toc_tree.find_parent(toc.name).name
            link_text = ''

            if @text =~ /^ *#{Regexp.quote(@parent_node_marker)} *$/
              link_text = File.basename path
            else
              link_text =
                @text.gsub(/^ *#{Regexp.quote(@parent_node_marker)} *, */,
                           '')
            end

            html += "<a href=\"#{path}\">#{link_text}</p>"

          else
            html += @text
          end

        end
      else
        # Exclude the current node since displaying a link to it on its own
        # site by default makes no sense. If necessary, this can still be
        # achieved by the user by wrapping the Liquid TOC tag in a HTML
        # list tag.
        html += toc.html true

      end
      html
    end

  end


  #########################################################################
  # `doctoc_up' Tag
  #########################################################################

  class DocTocUpTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
    end

    def render(context)

      html = ''
      toc_tree = context.registers[:site].data[:toc_tree]
      toc = toc_tree.
        find_parent('/' + File.dirname(context.registers[:page]['path']))

      # Exclude any top level nodes (usually there should only be one)
      # since they do not have a node associated with them.
      if toc_tree.root.children.collect { |c| c.name }.include? toc.name
        html = ''
      else
        link_text = ''

        if !@text.empty?
          link_text += @text.strip
        else
          link_text = File.basename(toc.name)
        end

        # Required for `_fallback/index.html' since it is automatically
        # generated which leads to `page.path' not being correct after
        # it has been attached to it artivicially when creating the
        # respective `IndexPage'. For some reason Jekyll does not seem
        # to catch up.
        if toc.name == File.dirname(context.registers[:page]['path'])
          toc.name = File.dirname toc.name
        end
        html += "<a href=\"#{toc.name}\">#{link_text}</a>"

      end

      html
    end

  end


  #########################################################################
  # `doctoc_previous' Tag
  #########################################################################

  class DocTocPreviousTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
      # Markers
      @prev_with_parens = 'prev_with_parens'
      @prev_only_name = 'only_name'
      @prev_only_prev = 'only_prev'
      @prev_only_prev_small_caps = 'only_prev_small_caps'
      @prev_custom = 'custom'
    end

    def render(context)
      html = ''

      path = File.dirname(File.join('/', context.registers[:page]['path']))
      prev_next_list = context.registers[:page]['doctoc_prev_next_list']

      index = nil
      if prev_next_list != nil
        index = prev_next_list.index(path)
      end

      prev_path = prev_next_list[index - 1]

      # The `nil' test ensures that Jekyll will not terminate when no
      # valid index is returned.
      if index != nil
        html = "<a href=\"#{prev_path}\">Previous</a>"
      end
      if !@text.empty?

        if @text =~ /^ *#{Regexp.quote(@prev_with_parens)} *$/
          html = "<a href=\"#{prev_path}\">Previous (\
#{File.basename prev_path})</a>"
        end

        if @text =~ /^ *#{Regexp.quote(@prev_only_name)} *$/
          html = "<a href=\"#{prev_path}\">#{File.basename prev_path}</a>"
        end

        if @text =~ /^ *#{Regexp.quote(@prev_only_prev)} *$/
          html = "<a href=\"#{prev_path}\">Previous</a>"
        end

        if @text =~ /^ *#{Regexp.quote(@prev_only_prev_small_caps)} *$/
          html = "<a href=\"#{prev_path}\">previous</a>"
        end

        if @text =~ /^ *#{Regexp.quote(@prev_custom)} *,/
          replacement =
            @text.gsub(/^ *#{Regexp.quote(@prev_custom)} *,/, '')
          html = "<a href=\"#{prev_path}\">#{replacement}</a>"
        end

      end

      html
    end

  end


  #########################################################################
  # `doctoc_next' Tag
  #########################################################################

  class DocTocNextTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
      # Markers
      @next_with_parens = 'next_with_parens'
      @next_only_name = 'only_name'
      @next_only_next = 'only_next'
      @next_only_next_small_caps = 'only_next_small_caps'
      @next_custom = 'custom'
    end

    def render(context)
      html = ''

      path = File.dirname(File.join('/', context.registers[:page]['path']))
      prev_next_list = context.registers[:page]['doctoc_prev_next_list']

      index = nil
      if prev_next_list != nil
        idx = prev_next_list.index(path)

        if idx >= (prev_next_list.length - 1)
          index = -1
        else
          index = idx
        end

      end

      next_path = prev_next_list[index + 1]

      # The `nil' test ensures that Jekyll will not terminate when no
      # valid index is returned.
      if index != nil
        html = "<a href=\"#{next_path}\">Next</a>"
      end
      if !@text.empty?

        if @text =~ /^ *#{Regexp.quote(@next_with_parens)} *$/
          html = "<a href=\"#{next_path}\">Next (\
#{File.basename next_path})</a>"
        end

        if @text =~ /^ *#{Regexp.quote(@next_only_name)} *$/
          html = "<a href=\"#{next_path}\">#{File.basename next_path}</a>"
        end

        if @text =~ /^ *#{Regexp.quote(@next_only_next)} *$/
          html = "<a href=\"#{next_path}\">Next</a>"
        end

        if @text =~ /^ *#{Regexp.quote(@next_only_next_small_caps)} *$/
          html = "<a href=\"#{next_path}\">next</a>"
        end

        if @text =~ /^ *#{Regexp.quote(@next_custom)} *,/
          replacement =
            @text.gsub(/^ *#{Regexp.quote(@next_custom)} *,/, '')
          html = "<a href=\"#{next_path}\">#{replacement}</a>"
        end

      end

      html
    end

  end

  # Register the Liquid tags
  Liquid::Template.register_tag('doctoc', Jekyll::DocTocTag)
  Liquid::Template.register_tag('doctoc_up', Jekyll::DocTocUpTag)
  Liquid::Template.register_tag('doctoc_prev', Jekyll::DocTocPreviousTag)
  Liquid::Template.register_tag('doctoc_next', Jekyll::DocTocNextTag)

end
