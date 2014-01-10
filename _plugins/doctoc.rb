###########################################################################
# TOC Plugin
###########################################################################

module Toc


  #========================================================================
  # Path Tree
  #========================================================================


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
          html << "<li><a href=\"#{c.name}\">#{File.basename c.name}</a></li>"
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

      # The semi-global state (storing something on the `Tree' class) is
      # necessary since `@children.empty?' within the `@children.each''s
      # block would not work since it could not access the outer scope
      # correctly.
      Tree.current_children_empty = @children.empty?  # Semi-global state!

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
      # Special case: the searched node is one of the children of the root
      # note.
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


  #========================================================================
  # Actual Plugin
  #========================================================================

  class Generator < Jekyll::Generator

    def initialize(arg)
      super
      @tree = {}
      @nested_list = ''
      @top_level_dir_name = '/pages'
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

      path_tree = Tree.new(TreeNode.new('root', ['data'],
                                        [TreeNode.new(@top_level_dir_name,
                                                      ['data'])]))

      path_tree.insert_pathes({@top_level_dir_name =>
                                @tree[@top_level_dir_name] })

      # TOC for the whole site

      toc = ''
      # Exclude the top level node since displaying `root' on the site
      # by default makes no sense. If necessary, this can still be achieved
      # by the user by wrapping the Liquid TOC tag in a HTML list tag.
      path_tree.find(@top_level_dir_name,
                     path_tree.root, true).children.each do |child|
        toc += child.html
      end
      site.pages.each do |page|
        page.data['doctoc'] = toc
      end

      # Attach the TOC to the site object so that it can be used elsewhere
      site.data[:toc_tree] = path_tree
    end
  end

end


###########################################################################
# TOC Tag
###########################################################################

module Jekyll

  class TocTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
      @text = text
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
          html += @text
        end
      else
        # Exclude the current node since displaying a link to it on its own
        # site by default makes no sense. If necessary, this can still be
        # achieved by the user by wrapping the Liquid TOC tag in a HTML
        # list tag.
        html += toc.html true
        html
      end
    end

  end

end

Liquid::Template.register_tag('doctoc', Jekyll::TocTag)
