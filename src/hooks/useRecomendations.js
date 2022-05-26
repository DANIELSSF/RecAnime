import { useEffect, useState } from "react";

export const useRecomendations = () => {

    const url = `https://api.jikan.moe/v4/recommendations/anime`;
    const [state, setState] = useState([]
    );

    useEffect(() => {
        fetch(url)
            .then(resp => resp.json())
            .then(datas => {
                const { data } = datas;
                data.map(img => {
                    const { entry } = img;
                    entry.map(imgs => {
                        setState(st => (
                            [...st,
                            {
                                id: imgs.mal_id,
                                images: imgs.images.jpg.large_image_url,
                                title: imgs.title
                            }]
                        ));
                    });
                });
            })
    }, [url])

    const aux = [];
    let result = state.filter((item) => {
        let fn = aux.find(er => er === item.id)
        if (!fn) {
            aux.push(item.id);
            return item;
        }
    });
    return result;
}