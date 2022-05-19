import { useEffect, useState } from "react"
import { getAnimeSearch } from "../helpers/getAnimeSearch";

const useFetchAnimeSearch = (animeName) => {
    const [animeSearch, setAnimeSearch] = useState({
        data: []
    });

    useEffect(() => {
        getAnimeSearch(animeName)
            .then(anime => {
                setAnimeSearch({
                    data: anime
                });
            });

    }, [animeName]);

    return animeSearch;
}
