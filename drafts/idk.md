{% comment %}
## .::0x0::Contexto::.

Llevo harto tiempo queriendo escribir sobre este tema, porque me lo sigo
encontrando una y otra vez en la vida real. Puede que todo esto te vaya a
parecer insignificante en la práctica, y entiendo completamente si ese es el
caso, pero yo soy seco para ceder ante ese bichito purista en mi cabeza y
quejarme de la gente que no usa HTTPS en sus redes internas o usa os.system() en
sus scripts estrictamente personales.  Dicho eso, mantengan sus brazos dentro
del vehículo en todo momento y tengan en mente que:
- Yo me quejo por todo
- Mi modelo de amenaza personal considera todos los escenarios posibles en un determinado momento.
- Yo me quejo por todo

## .::0x1::Muletillas::.

Para los fines de este post, me referiré como muletilla a cualquier práctica en programación que cumpla lo siguiente:
{% asciiart center %}
1. Es insegura.
2. Es común, aka. todos la conocen y se usa con frecuencia.
3. La gran mayoría de las veces, la mejor forma de resolver el problema no utiliza la muletilla.
{% endasciiart %}
Dicho de forma más burda, son como snippets de código inseguro en el inconsciente colectivo de todos los programadores; una especie de memoria muscular para ciertos problemas particulares

Por lo que he cachado, las muletillas son soluciones medias 'hack-y' para
problemas que se repiten con mucha frecuencia. Con el tiempo y el avance de las
tecnologías, estas se han seguido usando porque "siempre se ha hecho así".
Obvio que no creo que uno realmente haga el proceso mental para verbalizar esas
palabras exactas, pero al final del día así es como uno actúa cuando se ve
enfrentado a un problema que sabe que ya ha resuelto mil veces en el pasado.

## .::0x02::Ejemplos::.

[[[ 0x00 intro ]]]
muletilla son prácticas comunes que se hacen pq siempre se ha hecho/enseñado así
las normalizamos
Hay muletillas típicas
innerHTML no sé
no está malm hay casos límites
la gente no entiende bien estos casos límites
eg
    parametriza queries
    bien: whereRaw() sin input del usuario

    requests.get('https://example.com', verify=False)

    sudo su

en el sig. capítulo

.::0x03::"Siguiente Capítulo"::.
{% endcomment %}
