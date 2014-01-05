require 'pp'

module Toc

  class PathTree
    attr_accessor :root_node

    def initialize
      @root_node = PathNode.new
      @root_node.name = 'root'
    end

    def insert(node=@root_node, path_elements)
      # path_elements.each_with_index do |path_element, i|
      #   node.children.each do |child|
      #     if node.name == path_element
      #       node.insert(node.children[path_element], path_element[i..-1])
      #     else
      #       node.children << path_elements[i..-1]
      #     end
      #   end
      # end
    end

  end


  class PathNode
    attr_accessor :parent, :children, :name

    def initialize
      @name = nil
      @parent = nil
      @children = []
    end
  end


  class Generator < Jekyll::Generator

    def initialize(arg)
      super
      @tree = {}
      @nested_list = ''
    end

    def generate_tree(pathes)
      pathes.each do |path|
        current  = @tree
        path.split("/").inject("") do |sub_path, dir|
          sub_path = File.join(sub_path, dir)
          current[sub_path] ||= {}
          current = current[sub_path]
          sub_path
        end
      end
    end

    def generate_nested_list(prefix, node)
      @nested_list += "#{prefix}<ul>"
      node.each_pair do |path, subtree|
        # @nested_list +=
        #   "#{prefix}  <li>[#{path[1..-1]}] #{File.basename(path)}</li>"
        @nested_list +=
          # "#{prefix}  <li>[#{path[1..-1]}] #{File.basename(path)}</li>"
          "<li>#{path.split('/')[-1]}</li>"
        generate_nested_list(prefix + "  ", subtree) unless subtree.empty?
      end
      @nested_list += "#{prefix}</ul>"
    end

    def generate(site)
      # toc = PathTree.new()
      # site.pages.each do |page|
      #   page.data['toc'] = page.path.split('/')[1...-1]
      #   toc.insert page.path.split('/')[1...-1]
      # end
      # pp toc

      page_pathes = site.pages.each.collect { |page| page.path }

      generate_tree(page_pathes)

      pp @tree

      toc = generate_nested_list '', @tree
      site.pages.each do |page|
        page.data['toc'] = toc
      end
    end
  end

end
