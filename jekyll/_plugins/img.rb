module Jekyll
  module Tags
    class ImgTag < Liquid::Tag
      @@base_asset_path = "/assets/posts"
      def initialize(tag_name, img_name, token)
        super
        @image_name = img_name.strip
      end

      def render(context)
        slug = context.environments.first['page']['slug']
        post_year = context.environments.first['page']['date'].year
        "#{@@base_asset_path}/#{post_year}/#{slug}/#{@image_name}"
      end
    end
  end
end

Liquid::Template.register_tag('img', Jekyll::Tags::ImgTag)
