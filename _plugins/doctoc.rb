# -*- coding: utf-8 -*-


##########################################################################
# DISCLAIMER
##########################################################################
#
#
# Major flaws in this code:
# - NO TDD!
# - NO INLINE DOCUMENTATION!
# - Duplication
# - if-hell
# - (Semi-)Global state
# - Hard coupling
#
# Specifics:
# - Bulky ifs and RegEx matching in Tag classes; argument parsing for
#   Liquid tags is not unified
# - Messy argument hash handling in methods (`options')
# - The `Tree' class is not a 100% clean top-level entry point for its
#   `TreeNode's.
# - The `TreeNode' HTML rendering is messy.
# - Tag classes duplicate a lot of code among themselves (i.e. a
#   `previous' and a `next' tag have to do a lot of similar work).
#    Probably this is also a shortcoming of the Jekyll plugin API.
# - Both, `Tree' and `Generator' have a `@top_level_dir_name' vairable.
#   Only`Tree' shouldd have one.
# - `options' hash mixed with new-style default arguments. The `options'
#   hash should be preferred.
# - There are no conventions: Tree element name handling: `_' and ` '
#   (single space) are replaced all over the place, sometimes `/' in the
#   the beginning of path names is added or removed manually.
# - (There is the assumption that path names will always be Unix path
#   names which is only correct as long as Jekyll will not support them.)


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

      def sort_children_lexically(options)
        options = { :reverse => false }.merge(options)

        @children = @children.sort do |x, y|
          File.basename(x.name).casecmp File.basename(y.name)
        end

        @children = @children.reverse! if options[:reverse]
      end

      def sort_children_by_string_length(options)
        options = { :reverse => false }.merge(options)

        @children = @children.sort do |x, y|
          File.basename(x.name).length <=> File.basename(y.name).length
        end

        @children = @children.reverse! if options[:reverse]
      end

      def pp_child_list(child_list)
        child_list.collect { |c| c.name }
      end

      def sort_children_by_custom_list(options)
        options = { :reverse => false, :sort_arrays => {}, :level =>
          nil }.merge(options)

        array = []
        all_array = options[:sort_arrays]['all']
        array.push(*all_array) if all_array != nil
        level_array = options[:sort_arrays][options[:level]]
        array.push(*level_array) if level_array != nil

        array.reverse.each do |string|
          @children.each_with_index do |child, i|
            if File.basename(child.name) == string
              @children.insert(0, @children.delete_at(i))
            end
          end
        end

        @children = @children.reverse! if options[:reverse]
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

      def html(options)
        # The very existence of `TreeNode::html' duplicates a lot of
        # `TreeNode::htmlize' code. This is a shortcoming and completely
        # bad design. Why does it exist then? It really helps when treating
        # leaf node lists differently (non-wrapped individual `li'
        # elements).

        options = { :children_only => false, :add_class =>
          [nil, ''] }.merge(options)

        class_target = options[:add_class][0]
        if class_target != nil && class_target == @name
          class_attr = "class=\"#{options[:add_class][1].strip}\" "
        else
          class_attr = ''
        end

        children_empty_states = @children.collect { |c| c.children.empty? }
        is_flat = !children_empty_states.select { |c| c == true}.empty?

        html = []
        if !@children.empty? && is_flat && 0 != 0
          # Completely flat lists
          html << '<ul>'
          @children.each do |c|

            html <<
              "<li><a\
 #{class_attr}href=\"#{c.name.gsub(/ /, '_')}\">#{File.basename(c.name).gsub(/_/, ' ')}</a></li>"
          end
          html << '</ul>'
          html.join("\n")
        else
          # Arbitrarily deeply nested lists
          if options[:children_only]
            @children.each { |child| html <<
              child.htmlize([], :previous_children_empty => nil,
                            :add_class => options[:add_class]) }
            html.join("\n")
          else
            self.htmlize([], :previous_children_empty => nil,
                         :add_class => options[:add_class]).join("\n")
          end
        end
      end

      def htmlize(html, options)
        options = { :previous_children_empty => nil, :add_class =>
          [nil, ''], :counter => 0, :first_list_element =>
          false }.merge(options)

        # Counter handling for leaf node lists
        children_empty_states = @children.collect { |c| c.children.empty? }
        if !children_empty_states.empty?
          is_flat = !children_empty_states.select { |c| c == true}.empty?
        else
          is_flat = false
        end
        if !@children.empty? && is_flat
          options[:counter] = (@children.length - 1)
          options[:first_list_element] = true
        end

        class_target = options[:add_class][0]
        if class_target != nil && class_target == @name
          class_attr = "class=\"#{options[:add_class][1].strip}\" "
        else
          class_attr = ''
        end

        # if @children.empty? && options[:first_list_element]
        #   html << '<ul><!-- UL -->'
        #   options[:first_list_element] = false
        # end

        html <<
          "<li><a\
 #{class_attr}href=\"#{@name.gsub(/ /, '_')}\">#{File.basename(@name)}</a>"

        # Leaf nodes should not be lists themselves
        if !@children.empty?
          html << '<ul>'
        end

        # Semi-global state!
        #
        # The semi-global state (storing something on the `Tree' class) is
        # necessary since `@children.empty?' within the `@children.each''s
        # block would not work since it could not access the outer scope
        # correctly.
        Tree.current_children_empty = @children.empty?

        @children.each do |child|
          # Non-first list elements of a leaf node list decrease the
          # counter.
          if child.children.empty? && Tree.current_children_empty
            options[:counter] -= 1
          end

          child.htmlize html, :previous_children_empty =>
            Tree.current_children_empty, :add_class => options[:add_class],
          :counter => options[:counter], :first_list_element =>
            options[:first_list_element]

          # Unmark every node leaf list element which is not the first
          # one of this list.
          if child.children.empty? && Tree.current_children_empty
            options[:first_list_element] = false
          end
        end

        # if options[:previous_children_empty] == true &&
        #     @children.empty? == true && options[:counter] == 0
        #   html << "</ul><!-- /UL #{@name} - #{options[:counter]} -->"
        # end

        # Leaf nodes should not be lists themselves
        if !@children.empty?
          html << '</ul>'
        end

        # html << "</li><!-- #{options[:counter]} - #{options[:previous_children_empty]}-->"  # DEBUG
        html << "</li>"

        html
      end

    end


    class Tree
      attr_accessor :root, :prev_next_list, :top_level_dir_name

      def initialize(root, options)
        options = { :site => nil, :top_level_dir_name =>
          '/pages', :leaf_node_file_names =>
          ['index.html', 'index.markdown', 'index.md',
           'index.textile'] }.merge(options)

        @site = options[:site]
        @root = root
        @last_found_node = nil  # Semi-global state!
        # Note: Do not use the following variable anywhere else than in
        # `TreeNode::htmlize' since it is essentially semi-global state.
        # If you rebell still do it, at least update this comment!
        @current_children_empty  # Semi-global state!
        @prev_next_list = []
        @top_level_dir_name = options[:top_level_dir_name]
        @leaf_node_file_names = options[:leaf_node_file_names]

        # Custom sorting-related config
        @custom_sorting_config_file =
          File.join(File.join(@site.source,
                              File.join(@top_level_dir_name,
                                        '_config')), 'sorting.yml')
        @custom_sort_yaml_template = <<-eos
---
#==========================================================================
# Each key refers to an indentation level; e.g. `1' is the top level, `2'
# is the second indentation level, `3' the third one etc.
#==========================================================================

# Top level
1:
  - colors
  - animals

# Second level of indentation
2:
  - dark
  - bright

  - more nonsense
  - nonsense

# Third level of indentation
3:
  - orange
  - yellow
  - red

  - CDE Truck
  - ABC Truck

  - blue
  - purple

#==========================================================================
# The `all' section includes a sorting order which should be applied
# throughout all indentation levels.
#==========================================================================
all:
  - FGH Truck
  - IJK Truck
eos
        @custom_sort_array = self.generate_custom_sort_array
      end

      def Tree::current_children_empty
        @current_children_empty
      end

      def Tree::current_children_empty=(value)
        @current_children_empty = value
      end

      def siblings(node)
        node_name = node.name
        siblings = []
        if node_name != @top_level_dir_name
          siblings = find_parent(node_name).children.dup
          siblings.each_with_index do |child, i|
            if child.name == node_name
              siblings.delete_at i
            end
          end
        end
        siblings
      end

      def generate_custom_sort_array
        # Create the config directory if it does not exist yet.
        dirname = File.join(File.join(@site.source,
                                      File.join(@top_level_dir_name,
                                                '_config')))
        Dir.mkdir(dirname) unless Dir.exists?(dirname)

        # Create the sorting config file if it does not exist yet.
        file = File.join(File.join(@site.source,
                                   File.join(@top_level_dir_name,
                                             '_config')), 'sorting.yml')
        File.open(file, 'w') do |f|
          f.write @custom_sort_yaml_template
        end if !File.exists? file

        # Load the config data from the config file.
        config_data = {}
        if File.file? @custom_sorting_config_file
          config_data = YAML.load_file @custom_sorting_config_file

          # Provide an empty hash in case there were issues when loading
          # the config data.
          if config_data == false || config_data == nil
            config_data = {}
          end
        end

        config_data
      end

      def generate_prev_next_list(options)
        options = { :node => @root }.merge(options)
        @prev_next_list = []
        self.do_generate_prev_next_list :node => options[:node]
      end

      def do_generate_prev_next_list(options)
        options = { :node => @root }.merge(options)
        name = options[:node].name
        if name != @top_level_dir_name
          if !(@leaf_node_file_names.include? File.basename(name))
            @prev_next_list << name
          end
        end
        options[:node].children.each do |child|
          self.do_generate_prev_next_list :node => child
        end
      end

      def sort(options)
        options = { :node => @root, :order =>
          'lexical', :reverse => false, :level => nil }.merge(options)

        # Keep track of the current indentation level.
        if options[:level] == nil
          # `root'(0) and the top level dir(1) should be exluded.
          options[:level] = 1
        else
          options[:level] += 1
        end

        options[:node].children.each do |child|
          if options[:order] == 'lexical'
            child.sort_children_lexically :reverse => options[:reverse]
          elsif options[:order] == 'string_length'
            child.sort_children_by_string_length :reverse =>
              options[:reverse]
          elsif options[:order] == 'custom'
            child.sort_children_by_custom_list :reverse =>
              options[:reverse], :sort_arrays =>
              @custom_sort_array, :level => options[:level]
          else
            child.sort_children_lexically :reverse => options[:reverse]
          end
          self.sort :node => child, :reverse =>
            options[:reverse], :order => options[:order], :level =>
            options[:level]
        end

        # (Re-)Generate the previous/next list for this tree.
        self.generate_prev_next_list :node =>
          self.find(@top_level_dir_name, self.root, true)
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

        # (Re-)Generate the previous/next list for this tree.
        self.generate_prev_next_list :node =>
          self.find(@top_level_dir_name, self.root, true)
      end

      def insert_pathes(pathes)
        pathes.each_pair do |key, value|
          value.each_pair do |k, v|
            if !(@leaf_node_file_names.include? File.basename(k))
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

      def breadcrumb(node, options)
        options = { :parents => [], :separator => '', :no_html =>
          false }.merge(options)

        if options[:parents].empty?
          options[:parents] << node.name
        end
        parent_names = self.generate_breadcrumb_list node, options
        html = ''

        # Disregard the top level dir name (default: `pages') since it is
        # not linkable anyway.
        if parent_names[0] == @top_level_dir_name
          parent_names = parent_names[1..-1]
        end

        if !options[:no_html]
          options[:separator] = '<span> ' + options[:separator] +
            ' </span>'
          separator = options[:separator] + ' '
          parent_names[0..-2].each_with_index do |name, i|
            html << "<ul><li>#{separator if i > 0}<a\
 href=\"#{name.gsub(/ /, '_')}\">#{File.basename(name)}</a>"
          end

          # The child should not be link since it is the current page
          # anyway. Hide it if there are no parents.
          if parent_names.length > 1
            html << "<ul><li>#{separator}<\
span>#{File.basename(File.basename(parent_names[-1].gsub(/_/, ' ')))}</span></li><ul>"
          end

          parent_names[0..-2].each do |name|
            html << "</ul></li>"
          end

        else

          if options[:separator] == ''
            separator = '<span> / </span>'
          else
            separator = "<span> #{options[:separator]} </span>"
          end

          parent_names[0..-2].each_with_index do |name, i|
            html << "#{separator if i > 0}<a\
 href=\"#{name.gsub(/ /, '_')}\">#{File.basename(name)}</a>"
          end
          # The child should not be link since it is the current page
          # anyway. Hide it if there are no parents.
          if parent_names.length > 1
            html <<
              "#{separator}<span>#{File.basename(parent_names[-1])}<span>"
          end
        end

        html
      end

      def generate_breadcrumb_list(node, options)
        options = { :parents => [] }.merge(options)

        if node.name != @top_level_dir_name
          parent = self.find_parent(node.name)
          if parent.name != @top_level_dir_name
            options[:parents] << parent.name
            self.breadcrumb parent, :parents => options[:parents]
          end
        end

        options[:parents].reverse
      end

      def html(options)
        options = { :previous_children_empty => nil, :add_class =>
          [nil, ''] }.merge(options)

        @root.htmlize @root.html_string, options
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

        # Note: Jekyll uses Page::proces to determine the file extension
        # which then is used to determine the converter. That's why the
        # file extension has to be explicitely defined in the config file.
        self.process(@name)

        @fallback_template_template = <<-eos
---
layout: -
title: Fallback
permalink: /
---

<div class="fallback">
  <h2>{{ page.current_node }} <em>(Fallback)</em></h2>
  <p>There is not much to find on this page.</p>
  {% if page.parent != '' %}
  <p>Instead, go one level up to <strong><a href="{{ page.parent }}">{{ page.parent_name }}</a></strong>.</p>
{% endif %}
</div>
eos

        # Create the fallback template directory if it does not exist yet.
        dirname = File.join(File.join(site.source,
                                      File.join(top_level_dir_name,
                                                '_fallback')))
        Dir.mkdir(dirname) unless Dir.exists?(dirname)

        # Create the fallback template if it does not exist yet.
        file = File.join(File.join(site.source,
                                   File.join(top_level_dir_name,
                                             '_fallback')), name)

        # Write sample data to the fallback template.
        File.open(file, 'w') do |f|
          f.write @fallback_template_template
        end if !File.exists? file

        # Process the fallback template.
        self.read_yaml(File.join(base,
                                 File.join(top_level_dir_name,
                                           '_fallback')), name)
        data.each_pair { |key, value| self.data[key] = value }
      end

    end


    class Generator < Jekyll::Generator
      safe true
      priority :low

      def initialize(arg)
        super
        @tree = {}
        @nested_list = ''
        @top_level_dir_name = '/pages'
        @prev_next_list = []
        @leaf_node_file_names = ['index.html', 'index.markdown',
                                 'index.md', 'index.textile']
        @index_page_file_name = "index.html"
      end

      def generate_index_pages(site, pathes, path_tree, toc)
        pathes.each_pair do |key, value|
          value.each_pair do |k, v|
            parent_path = path_tree.find_parent(k).name
            if parent_path == @top_level_dir_name
              parent_path = ''
              has_parent = 'false'
            else
              has_parent = 'true'
            end
            if !(@leaf_node_file_names.include? File.basename(k))
              if !File.file?(File.join(site.source,
                                       File.join(k,
                                                 @index_page_file_name)))
                index_page =
                  IndexPage.new(site, site.source,
                                '/',
                                @index_page_file_name, {
                                  'parent' => parent_path,
                                  'has_parent' => has_parent,
                                  'parent_name' =>
                                  File.basename(parent_path),
                                  'doctoc' => toc,
                                  'path' =>
                                  File.join(path_tree.find(k, path_tree.root).name.gsub(/^\//, ''),
                                            @index_page_file_name),
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

      def generate_tree(pathes)
        pathes.each do |path|
          current = @tree
          counter = 0

          path.split("/").inject("") do |sub_path, dir|
            sub_path = File.join(sub_path, dir)
            sub_path = sub_path.gsub(/_/, ' ')

            if (current[sub_path] == nil || current[sub_path] == false) &&
                !(@leaf_node_file_names.include? sub_path)
              current[sub_path] = { }
            end

            current = current[sub_path]

            sub_path
          end
        end
      end

      def generate(site)
        # Set the name for the top level directory. This will determine
        # the root of the URL slug. If there is no `doctoc_dir' config
        # entry in the config  file (`_config.yml' in the latest Jekyll
        # version), use the default top level dir name (`/pages').
        begin
          @top_level_dir_name = '/' +
            site.config['doctoc_dir'].gsub(/\/$/, '').gsub(/^\//, '') ||
            @top_level_dir_name

          if site.config['doctoc_fallback_extension']
            @index_page_file_name =
              "index.#{site.config['doctoc_fallback_extension'].strip}"
          end
        rescue
          # Ignore. If there is no config option, the default will be used
          # anyway.
        end

        page_pathes = site.pages.each.collect { |page| page.path }

        generate_tree(page_pathes)

        # The version of `path_tree' that is attached to the `site' object
        # is called `toc_tree' to indicate that those two versions of the
        # same tree object can differ at times.
        #
        # Example:
        #   1. `path_tree' is created
        #   2. `path_tree' is modified
        #   3. `path_tree' gets attached to `site' as `toc_tree'
        #
        #   Between 3. and 1. there may be differences caused by 2.
        path_tree =
          Tree.new(TreeNode.new('root', ['data'],
                                [TreeNode.new(@top_level_dir_name,
                                              ['data'])]), :site => site,
                   :top_level_dir_name => @top_level_dir_name,
                   :leaf_node_file_names => @leaf_node_file_names)

        path_tree.insert_pathes({ @top_level_dir_name =>
                                  @tree[@top_level_dir_name] })

        path_tree.sort :node => path_tree.root, :order =>
          'lexical', :reverse => false

        toc = ''
        # Exclude the top level node since displaying `root' on the site
        # by default makes no sense. If necessary, this can still be
        # achieved by the user by wrapping the Liquid TOC tag in a HTML
        # list tag.
        path_tree.find(@top_level_dir_name,
                       path_tree.root, true).children.each do |child|
          toc += child.html :children_only => false
        end

        # Add shared data to each page
        site.pages.each do |page|
          page.data['doctoc'] = toc
        end

        # Attach the TOC to the site object so that it can be used
        # elsewhere.
        site.data[:toc_tree] = path_tree

        # Attach the name of the top level directory to the site so that
        # tags can use it.
        site.data[:doctoc_top_level_dir_name] = @top_level_dir_name

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
      @highlight_current_node_marker = 'highlight-current-node'

      # Default CSS highlighting class
      @doctoc_highlight_class = 'doctoc-highlight'
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
      path = File.dirname(context.registers[:page]['path']).gsub(/_/, ' ')
      toc = toc_tree.find('/' + path, toc_tree.root, true)

      # In case there is no TOC node found or the TOC node that has been
      # found is a leaf node there should not be any HTML emitted.
      if toc == nil || toc.children.empty?
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

            html += "<a href=\"#{path.gsub(/ /, '_')}\">#{link_text}</p>"

          else
            if @text =~ / *#{Regexp.quote(@parent_node_marker)} */
              html += @text
            end
          end

        end
      else
        # Exclude the current node since displaying a link to it on its own
        # site by default makes no sense. If necessary, this can still be
        # achieved by the user by wrapping the Liquid TOC tag in a HTML
        # list tag.
        if @text =~ / *#{Regexp.quote(@parent_node_marker)} */
          html += toc.html :children_only => true
        end

      end

      # Check for additional text supplied to the tag.
      if !@text.empty? && toc.respond_to?(:name)
        # Highlight the current node
        if @text =~ / *#{Regexp.quote(@highlight_current_node_marker)} */
          highlight_class = ''

          if @text =~
              /^ *#{Regexp.quote(@highlight_current_node_marker)} *$/
            highlight_class = @doctoc_highlight_class
          else
            highlight_class =
              @text.gsub(/^ *#{Regexp.quote(@highlight_current_node_marker)} *, */, '')
          end

          # Attach the necessary children only, leaving out the top level
          # nodes.
          toc_tree.find(context.registers[:site].data[:doctoc_top_level_dir_name],
                        toc_tree.root, true).children.each do |child|
            html += child.html :children_only => false, :add_class =>
              [toc.name, highlight_class]
          end

        end
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
      path = File.dirname(context.registers[:page]['path']).gsub(/_/, ' ')
      toc = toc_tree.find_parent('/' + path)


      if toc.respond_to? :name
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
          html += "<a href=\"#{toc.name.gsub(/ /, '_')}\">#{link_text}</a>"

        end
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

      path =
        File.dirname(File.join('/',
                               context.registers[:page]['path'])).gsub(/_/,
                                                                       ' ')
      prev_next_list =
        context.registers[:site].data[:toc_tree].prev_next_list

      index = nil
      if prev_next_list != nil
        index = prev_next_list.index(path)
      end


      # The `nil' test ensures that Jekyll will not terminate when no
      # valid index is returned.
      if index != nil
        prev_path = prev_next_list[index - 1]
        html = "<a href=\"#{prev_path.gsub(/ /, '_')}\">Previous</a>"
      end

      if !@text.empty?
        if prev_path != nil
          prev_path = prev_path.gsub(/ /, '_')
        end

        if @text =~ /^ *#{Regexp.quote(@prev_with_parens)} *$/
          html = "<a href=\"#{prev_path}\">Previous (\
#{File.basename prev_path})</a>"
        end

        if @text =~ /^ *#{Regexp.quote(@prev_only_name)} *$/
          html = "<a href=\"#{prev_path}\"\
>#{File.basename prev_path}</a>"
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
          html = "<a href=\"#{prev_path}\"\
>#{replacement}</a>"
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

      path =
        File.dirname(File.join('/',
                               context.registers[:page]['path'])).gsub(/_/,
                                                                       ' ')
      prev_next_list =
        context.registers[:site].data[:toc_tree].prev_next_list

      index = nil
      if prev_next_list != nil
        idx = prev_next_list.index(path)

        if idx != nil
          if idx >= (prev_next_list.length - 1)
            index = -1
          else
            index = idx
          end
        end

      end


      # The `nil' test ensures that Jekyll will not terminate when no
      # valid index is returned.
      if index != nil
        next_path = prev_next_list[index + 1]
        html = "<a href=\"#{next_path.gsub(/ /, '_')}\">Next</a>"
      end

      if !@text.empty?
        if next_path != nil
          next_path = next_path.gsub(/ /, '_')
        end

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


  #########################################################################
  # `doctoc_sort' Tag
  #########################################################################

  class DocTocSortTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text

      # Markers
      @lexical_sort_marker = 'lexical'
      @string_length_sort_marker = 'string_length'
      @custom_sort_marker = 'custom'
    end

    def render(context)
      html = ''
      sort_order = 'lexical'
      reverse = false
      reverse_marker = ''
      toc_tree = context.registers[:site].data[:toc_tree]

      # Sort the site-wide TOC tree
      context.registers[:site].data[:toc_tree].sort :node =>
        toc_tree.root, :order => 'lexical', :reverse => true

      if !@text.empty?

        # Sort order: lexical
        if @text =~ /^ *#{Regexp.quote(@lexical_sort_marker)} *$/
          sort_order = 'lexical'
        elsif @text =~ /^ *#{Regexp.quote(@lexical_sort_marker)} *,/
          sort_order = 'lexical'
          # Reverse sort order
          reverse_marker =
            @text.gsub(/^ *#{Regexp.quote(@lexical_sort_marker)} *,/,
                       '').strip
        end

        # Sort order: string length
        if @text =~ /^ *#{Regexp.quote(@string_length_sort_marker)} *$/
          sort_order = 'string_length'
        elsif @text =~ /^ *#{Regexp.quote(@string_length_sort_marker)} *,/
          sort_order = 'string_length'
          # Reverse sort order
          reverse_marker =
            @text.gsub(/^ *#{Regexp.quote(@string_length_sort_marker)} *,/,
                       '').strip
        end

        # Sort order: custom
        if @text =~ /^ *#{Regexp.quote(@custom_sort_marker)} *$/
          sort_order = 'custom'
        elsif @text =~ /^ *#{Regexp.quote(@custom_sort_marker)} *,/
          sort_order = 'custom'
          # Reverse sort order
          reverse_marker =
            @text.gsub(/^ *#{Regexp.quote(@custom_sort_marker)} *,/,
                       '').strip
        end

      else
        toc_tree.sort :node => toc_tree.root, :order =>
          'lexical', :reverse => true
      end

      if reverse_marker == 'reverse'
        reverse = true
      else
        reverse = false
      end

      toc_tree.sort :node => toc_tree.root, :order =>
        sort_order, :reverse => reverse

      '' # This tag should not render anything.
    end

  end


  #########################################################################
  # `doctoc_breadcrumb' Tag
  #########################################################################

  class DocTocBreadcrumbTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
      # Marker
      @nitpicky_marker = 'nitpicky'
    end

    def render(context)
      html = ''
      toc_tree = context.registers[:site].data[:toc_tree]
      path = File.dirname(context.registers[:page]['path']).gsub(/_/, ' ')
      toc = toc_tree.find('/' + path, toc_tree.root, true)

      if toc.respond_to?(:name) && toc.name != toc_tree.top_level_dir_name
        current = toc

        if !@text.empty?

          if @text =~ /^ *#{Regexp.quote(@nitpicky_marker)} *$/
            html = toc_tree.breadcrumb(current, :parent => '')
          elsif @text =~ /^ *#{Regexp.quote(@nitpicky_marker)} *,/
            separator =
              @text.gsub(/^ *#{Regexp.quote(@nitpicky_marker)} *,/,
                         '').strip
            html = toc_tree.breadcrumb(current, :parent => '',
                                       :separator => separator)
          else
            html = toc_tree.breadcrumb(current, :parent => '',
                                       :separator => @text.strip,
                                       :no_html => true)
          end

        else
          html = toc_tree.breadcrumb(current, :parent => '', :no_html =>
                                     true, :separator => '')
        end

        html
      else
        ''  # Do not render anything.
      end
    end

  end


  #########################################################################
  # `doctoc_siblings' Tag
  #########################################################################

  class DocTocSiblingsTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
    end

    def render(context)
      html = ''
      toc_tree = context.registers[:site].data[:toc_tree]
      path = File.dirname(context.registers[:page]['path']).gsub(/_/, ' ')
      toc = toc_tree.find('/' + path, toc_tree.root, true)

      if  toc.respond_to?(:name) &&
          toc.name != toc_tree.top_level_dir_name
        siblings = toc_tree.siblings toc
        if siblings.length > 0
          html << @text.strip
          html << '<ul>'
          siblings.each do |sibling|
            html << "<li><a\
 href=\"#{sibling.name}\">#{File.basename(sibling.name)}</a></li>"
          end
          html << '</ul>'
        end
      else
        ''  # Do not render anything.
      end

      html
    end

  end


  #########################################################################
  # `doctoc_children' Tag
  #########################################################################

  class DocTocChildrenTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
    end

    def render(context)
      html = ''
      toc_tree = context.registers[:site].data[:toc_tree]
      path = File.dirname(context.registers[:page]['path']).gsub(/_/, ' ')
      toc = toc_tree.find('/' + path, toc_tree.root, true)

      if toc.respond_to?(:name) &&
          toc.name != toc_tree.top_level_dir_name
        children = toc.children
        if children.length > 0
          html << @text.strip
          html << '<ul>'
          children.each do |child|
            html << "<li><a\
 href=\"#{child.name}\">#{File.basename(child.name)}</a></li>"
          end
          html << '</ul>'
        end
      else
        ''  # Do not render anything.
      end

      html
    end

  end


  #########################################################################
  # `doctoc_children_of' Tag
  #########################################################################

  class DocTocChildrenOfTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
    end

    def render(context)
      html = ''
      toc_tree = context.registers[:site].data[:toc_tree]
      if @text =~ /^ *[^,] *$/
        path = @text.strip
      else
        path = @text.gsub(/,.*/, '').strip
      end
      path = path.gsub(/_/, ' ').gsub(/\/$/, '').gsub(/^\//, '')
      toc = toc_tree.find('/' + path, toc_tree.root, true)

      # if toc.name != toc_tree.top_level_dir_name
      children = toc.children
      if children.length > 0
        if @text =~ /.*,.*/
          html << @text.gsub(/^.*,/, '').strip
        end
        html << '<ul>'
        children.each do |child|
          html << "<li><a\
 href=\"#{child.name.gsub(/ /, '_')}\">#{File.basename(child.name)}</a></li>"
        end
        html << '</ul>'
      end
      # else
      #   ''  # Do not render anything.
      # end

      html
    end

  end


  #########################################################################
  # `doctoc_subtree_of' Tag
  #########################################################################

  class DocTocSubtreeOfTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
    end

    def render(context)
      html = ''
      subtree_html = ''
      toc_tree = context.registers[:site].data[:toc_tree]
      if @text =~ /^ *[^,] *$/
        path = @text.strip
      else
        path = @text.gsub(/,.*/, '').strip
      end
      path = path.gsub(/_/, ' ').gsub(/\/$/, '').gsub(/^\//, '')
      toc = toc_tree.find('/' + path, toc_tree.root, true)

      subtree_html << toc.html(:children_only => true)
      if subtree_html != ''
        if @text =~ /.*,.*/
          html << @text.gsub(/^.*,/, '').strip
        end
        html << '<ul>'
        html << subtree_html
        html << '</ul>'
      end

      html
    end

  end

  # Register the Liquid tags
  Liquid::Template.register_tag('doctoc', Jekyll::DocTocTag)
  Liquid::Template.register_tag('doctoc_up', Jekyll::DocTocUpTag)
  Liquid::Template.register_tag('doctoc_prev', Jekyll::DocTocPreviousTag)
  Liquid::Template.register_tag('doctoc_next', Jekyll::DocTocNextTag)
  Liquid::Template.register_tag('doctoc_sort', Jekyll::DocTocSortTag)
  Liquid::Template.register_tag('doctoc_breadcrumb',
                                Jekyll::DocTocBreadcrumbTag)
  Liquid::Template.register_tag('doctoc_siblings',
                                Jekyll::DocTocSiblingsTag)
  Liquid::Template.register_tag('doctoc_children',
                                Jekyll::DocTocChildrenTag)
  Liquid::Template.register_tag('doctoc_children_of',
                                Jekyll::DocTocChildrenOfTag)
  Liquid::Template.register_tag('doctoc_subtree_of',
                                Jekyll::DocTocSubtreeOfTag)

end
