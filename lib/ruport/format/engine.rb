class InvalidPluginError < RuntimeError; end

module Ruport
  class Format::Engine
    require "forwardable"
    require "enumerator"
    class << self

      include Enumerable
      include MetaTools
      extend Forwardable

      attr_accessor :engine_classes
      attr_reader :plugin 
      attr_reader :data
      attr_accessor :class_binding
      attr_reader :options
      
      def_delegator :@data, :each
      private :attribute, :attributes, :singleton_class, :action

      def renderer(&block)
        block = lambda { data } unless block_given?
        singleton_class.send(:define_method, :render,&block)
      end
      
      def alias_engine(klass,name)
        singleton_class.send(:define_method,:engine_name) { name }
        Format::Engine.engine_classes ||= {}
        Format::Engine.engine_classes[name] = klass
      end

      def data=(stuff)
        return unless stuff
        @data = stuff
        active_plugin.data = stuff.dup if active_plugin
      end

      def options=(opts)
        @options = opts
        active_plugin.options = options if active_plugin
      end
      
      def active_plugin
        return yield(@format_plugins[:current]) if block_given?
        @format_plugins[:current]  
      end

      def plugin=(p)
        if @format_plugins[p].nil?
          raise(InvalidPluginError, 
                'The requested plugin and engine combination is invalid') 
        end

        @plugin = p
        @format_plugins[:current] = @format_plugins[p].dup
        @format_plugins[:current].data = self.data.dup if self.data 
      end
      
      def apply_erb
       active_plugin.data = 
         ERB.new(active_plugin.data).result(class_binding || binding)
      end
 
      def render
        raise "No plugin specified" unless plugin
        active_plugin.data = data.dup
        if active_plugin.respond_to? :init_plugin_helper
           active_plugin.init_plugin_helper(self)
        end
      end

      def flush_data
        self.data = nil
      end
      
      def accept_format_plugin(klass) 
        format_plugins[klass.plugin_name] = klass
      end

      private  

      def format_plugins
        @format_plugins ||= {}
      end

      def plugin_names
        format_plugins.keys
      end

      def plugins
        format_plugins.values
      end 
      
      def method_missing(id,*args)
        active_plugin.extend active_plugin.helpers[engine_name]
        super unless active_plugin.respond_to?("#{id}_helper")
        return active_plugin.send("#{id}_helper",self)
      end

    end
    
    private_class_method :new
  end
  
  class Format::Engine::Graph < Ruport::Format::Engine
    
    renderer do
      super
      active_plugin.render_graph
    end
  
    alias_engine Graph, :graph_engine
    Ruport::Format.build_interface_for Graph, :graph
  
  end
 
 class Format::Engine::Invoice < Ruport::Format::Engine

    # order meta data
    attributes [ :customer_info, :company_info, 
                 :comments, :order_info, :title]
   
    renderer do
      super
      build_headers
      build_body
      build_footer
      active_plugin.render_invoice
    end
  
    alias_engine Invoice, :invoice_engine
    Ruport::Format.build_interface_for Invoice, :invoice
  
  end

  class Format::Engine::Table < Format::Engine      
        
     renderer do
        super
        active_plugin.rendered_field_names = "" 
        build_field_names if (data.respond_to?(:column_names) && 
                              data.column_names && show_field_names)
        a = active_plugin.render_table
     end

    class << self

      def rewrite_column(key,&block)
        data.each { |r| r[key] = block[r] }
      end

      def num_cols
        data[0].to_a.length
      end

      def prune(limit=data[0].length)
        limit.times do |field|
          last = ""
          data.each_cons(2) { |l,e|
            next if field.nonzero? && e[field-1] 
            last = l[field] if l[field]
            e[field] = nil if e[field] == last
          }
        end
      end
      
      attr_accessor :show_field_names
      
      private
      
      def build_field_names
        if active_plugin.respond_to?(:build_field_names)
          active_plugin.rendered_field_names = 
            active_plugin.build_field_names
        end
      end

    end  
    
      alias_engine Table, :table_engine
      Format.build_interface_for Table, :table
      self.show_field_names = true
  end

  class Format::Engine::Document < Format::Engine
    
    renderer do
      super
      apply_erb if erb_enabled
      apply_red_cloth if red_cloth_enabled
      active_plugin.render_document
    end

    class << self
      
      attr_accessor :red_cloth_enabled
      attr_accessor :erb_enabled
      
      def apply_red_cloth
        require "redcloth"
        active_plugin.data = RedCloth.new(active_plugin.data).to_html
      end
          
    end
    
    alias_engine Document, :document_engine
    Format.build_interface_for Document, :document 
  end


end
