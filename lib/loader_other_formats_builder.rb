module LoaderOtherFormatsBuilder
  def self.included(base)
    base.class_eval do
      def link_to_with_query_parameters(name, url={}, options={})
        params = @view.request.query_parameters.except(:page, :format).except(*url.keys)
        if name == 'XML'
          url = { :controller => 'loader', :action => 'export', :query_id => options[:query_id] }
        else
          url = {:params => params, :page => nil, :format => name.to_s.downcase}.merge(url)
        end
        caption = options.delete(:caption) || name
        html_options = { :class => name.to_s.downcase, :rel => 'nofollow' }.merge(options)
        @view.content_tag('span', @view.link_to(caption, url, html_options))
      end
    end
  end
end
