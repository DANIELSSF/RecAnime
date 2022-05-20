import { useEffect, useState } from "react"
import { getAnimeSearch } from "../helpers/getAnimeSearch";

export const useFetchAnimeSearch = (name) => {
    const [animeSearch, setAnimeSearch] = useState({
        data: []
    });

    useEffect(() => {
        getAnimeSearch(name)
            .then(anime => {
                setAnimeSearch({
                    data: anime
                });
            });

    }, [name]);

    return animeSearch;
}
