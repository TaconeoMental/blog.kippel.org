---
layout: post
title: "Plugins para blog.kippel.org"
tags: dev meta
---

{% assign asciiart_padding = 0 %}
{% assign asciiart_align = 'left' %}

Hace poco migré todo mi blog antiguo (sigint.in, que en paz descanse) a este
nuevo dominio y de pasada hice privado el repositorio con el código del
proyecto. Una verdadera pérdida para la comunidad open-source, lo sé.  En sí no
tenía ninguna gracia: Uso Jekyll con un theme custom -minimalista porque no
le sé al frontend- y todo dockerizado y pegado con scotch para que no sea tan
tedioso hacer cambios. La única pérdida real (con hartas comillas) son los mini
plugins que escribí, que probablemente le podrían servir a alguien para su
propio blog. Son bien chicos así que los dejo acá.

## Plugin 1: img

Al igual que su nombre, este plugin es fome y corto. De hecho, este es todo el
código:

{% highlight ruby %}
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
{% endhighlight %}

Básicamente, crea un tag de Liquid, 'img', que devuelve la ruta absoluta de un
asset para el post en cuestión. Existen muchísimos proyectos parecidos que
buscan solucionar la gestión de assets en Jekyll, pero no me convenció ninguno
realmente.

Como contexto, antes tenía un solo directorio en donde guardaba los assets para
todo el blog, principalmente las imagenes para los posts. Se veía así:

![Assets originales]({% img sigint.in_assets.png %}){:class="imgcenter"}

Y para referenciarlas en un post, tenía que escribirlo así:

{% highlight markdown %}
![ilo4-dashboard](/assets/images/2024-ilo4-disclosure-dashboard.png)
{% endhighlight %}

Si... Por otro lado, con este plugin la estructura cambia a algo así:

{% asciiart left %}
.
|-- assets
|   \-- posts
|       |-- 2023
|       |   `-- SLUG-1
|       |       `-- asset-1.png
|       `-- 2024
|           `-- SLUG-2
`-- posts
    |-- 2023
    |   `-- 2023-11-09-SLUG-1.md
    `-- 2024
        \-- 2024-05-22-SLUG-2.md
{% endasciiart %}

En donde los assets de **posts/2023/2023-11-09-SLUG-1.md** están en
**assets/posts/2023/SLUG-1**, y pueden referenciarse así:

{% highlight liquid %}
{% raw %}![img alt]({% img asset-1.png %}){% endraw %}
{% endhighlight %}

Es una tontera al final del día, pero tiene esa simpleza que muchos otros
proyectos no tienen. Hasta ahora me ha funcionado muy bien y estoy muy cómodo
con esta forma de estructurar los archivos.


## Plugin 2: asciiart

Este es un poco más entretenido, pero sigue siendo bien simple en principio. El
código es un poco más largo, así que lo dejo al final.

Una de las cosas que sí o sí quería que hubiera en mi blog era ASCII Art. El
problema es que Jekyll funciona con un sistema de plantillas que genera código
HTML estático y estos dibujos dependen mucho de los espacios en blanco, saltos
de línea y otros factores. Esto hace bien dificil hacer que queden bien
formateados en el sitio y casi imposible moverlos o alinearlos horizontalmente.
Este plugin soluciona todo eso con un nuevo bloque de Liquid: 'asciiart'.

El bloque **asciiart** recibe dos argumentos opcionales: *align* y *padding*.
*align* puede tomar los valores *left*, *center* o *right* y *padding* toma un
número entero.

Por ejemplo:
{% highlight liquid %}
{% raw %}
{% asciiart left %}
|\---/|
| o_o |
 \_^_/
{% endasciiart %}
{% endraw %}
{% endhighlight %}
{% asciiart left %}
|\---/|
| o_o |
 \_^_/
{% endasciiart %}


{% highlight liquid %}
{% raw %}
{% asciiart left, 20 %}
|\---/|
| o_o |
 \_^_/
{% endasciiart %}
{% endraw %}
{% endhighlight %}
{% asciiart left, 20 %}
|\---/|
| o_o |
 \_^_/
{% endasciiart %}


{% highlight liquid %}
{% raw %}
{% asciiart center %}
|\---/|
| o_o |
 \_^_/
{% endasciiart %}
{% endraw %}
{% endhighlight %}
{% asciiart center %}
|\---/|
| o_o |
 \_^_/
{% endasciiart %}


{% highlight liquid %}
{% raw %}
{% asciiart right %}
|\---/|
| o_o |
 \_^_/
{% endasciiart %}
{% endraw %}
{% endhighlight %}
{% asciiart right %}
|\---/|
| o_o |
 \_^_/
{% endasciiart %}

También es posible configurar valores por defecto para evitar repetición
innecesaria.
{% highlight liquid %}
{% raw %}
{% assign asciiart_padding = 5 %}
{% assign asciiart_align = 'right' %}
{% asciiart %}
|\---/|
| o_o |
 \_^_/
{% endasciiart %}
{% endraw %}
{% endhighlight %}
{% asciiart right,5 %}
|\---/|
| o_o |
 \_^_/
{% endasciiart %}

{% asciiart %}
*Gato sacado de https://www.asciiart.eu/animals/cats
{% endasciiart %}

No hay mucho más que decir del plugin. Lo uso literalmente en todas partes y ya
no debo andar preocupado de cómo se va a ver el dibujito alineado a la derecha
en el navegador de un teléfono.

Este es el código:
{% highlight ruby %}
module Jekyll
  module Tags
    class AsciiArtBlock < Liquid::Block
      def initialize(tag_name, text, token)
        super
        # Argument format: (left|right|center), (\d|[a-zA-Z0-9_]+)
        align, padding = text.split(',').map(&:strip)
        @align = align || ''
        @padding = padding
      end

      def escape_xhtml(text)
        # Note: > does not need to be escaped in XML content, but HTML4 spec
        # says "should escape" to avoid problems with older user agents
        # Note: Characters with restricted/discouraged usage are left unchanged
        text.gsub(/[&<>]|[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\u10000-\u10FFF]/) do | match |
          case match
          when '&' then '&amp;'
          when '<' then '&lt;'
          when '>' then '&gt;'
          else "&#x#{match.ord};"
          end
        end
      end

      def normalize_lengths(text)
        # Normalize line lengths to maintain picture's shape when right aligned
        lines = text.lines.map(&:chomp).map(&:rstrip)
        # The first line is usually empty because the picture starts one line
        # after the {% raw %}{% asciiart %}{% endraw %} block
        if lines[0].empty?
          lines = lines.drop(1)
        end
        max_length = lines.map(&:length).max # Longest line
        padded_lines = lines.map { |line| line.ljust(max_length) }
        padded_lines.join("\n")
      end

      def apply_padding(text, align, padding)
        lines = text.lines.map(&:chomp)
        padded_lines = lines.map do |line|
          if align == 'left'
            line = line.prepend(" " * padding)
          elsif align == 'right'
            line = line.concat(" " * padding)
          end
          line
        end
        padded_lines.join("\n")
      end

      def get_padding(ctx)
        padding_int = Integer(@padding, exception: false)
        # Test if argument passed is an integer or a variable in the ctx's
        # namespace. Set the padding as 10 otherwise
        padding_int || ctx[@padding] || ctx["asciiart_padding"] || 0
      end

      def get_align(ctx)
        if ['left', 'center', 'right'].include?(@align)
          return @align
        end
        ctx[@align] || ctx["asciiart_align"] || 'center'
      end

      def render(context)
        real_padding = get_padding(context)
        real_align = get_align(context)
        content = escape_xhtml(normalize_lengths(super(context)))
        content = apply_padding(content, align=real_align, padding=real_padding)
        "<pre class=\"ascii-art-#{real_align}\">#{content}</pre>"
      end
    end
  end
end

Liquid::Template.register_tag('asciiart', Jekyll::Tags::AsciiArtBlock)
{% endhighlight %}
