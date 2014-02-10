# DocToc - Jekyll Documentation Helper

DocToc is a documentation helper plugin for Jekyll.

It scans a nested directory structure in the root of your Jekyll project, constructs a hierarchical tree from it and provides various navigation elements in the form of Liquid tags. It also offers different sorting instructions and automatically adds missing index pages in directories where none are specified so that no navigation link points to a non-existing page.

You can see it document itself [here](http://nounch.github.io/doctoc-documentation/doc/About/).

## About This Project

This repository is a complete Jekyll project which acts as development environment for the DocToc plugin. The plugin itself lives in `_plugins/`.

## Usage

``` bash
git clone git://github.com/nounch/doctoc.git doctoc
cp -r doctoc/_plugins/doctoc.rb /path/to/your/jekyll/project/_plugins/
# ...
# Go to your project.
# Set up your layout.
# Add a nested directory structure in the root of your Jekyll project.
# ...
jekyll serve --watch --port 8002
# (Or build it with `jekyll build' and serve the resulting `_site'
# directory as a static site.)
```
