
export const getRecomendations = async () => {
    const url = `https://api.jikan.moe/v4/recommendations/anime`;
    const resp = await fetch(url);
    const { data } = await resp.json();

    
    const recomendations = data.map(img => {
        return {
            idkey:img.mal_id,
            id1: img.entry[0]?.mal_id,
            id2: img.entry[1]?.mal_id,
            title1: img.entry[0]?.title,
            title2: img.entry[1]?.title,
            url1: img.entry[0]?.images?.jpg.large_image_url,
            url2: img.entry[1]?.images?.jpg.large_image_url
        }

    })
    return recomendations;

}