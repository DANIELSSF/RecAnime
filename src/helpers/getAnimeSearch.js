
export const getAnimeSearch = async (name) => {

    const url = `https://api.jikan.moe/v4/anime?q=${name}`;
    const resp = await fetch(url);
    const { data } = await resp.json();

    const nameAnime = data.map(anime => {
        return {
            id: anime.mal_id,
            url: anime.images?.jpg.large_image_url,
            title: anime.title,
            source: anime.source,
            episodes: anime.episodes,
            status: anime.status,
            score: anime.score,
            synopsis: anime.synopsis,
            year: anime.year
        }
    })
    return nameAnime;
}