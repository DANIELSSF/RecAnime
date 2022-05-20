import { useEffect, useState } from "react"
import { getAnimeSearch } from "../helpers/getAnimeSearch";
import PropTypes from 'prop-types';

export const useFetchAnimeSearch = (name) => {
    const [animeSearch, setAnimeSearch] = useState({
        data: [],
        loading: false
    });

    useEffect(() => {
        getAnimeSearch(name)
            .then(anime => {
                setAnimeSearch({
                    data: anime,
                    loading: true
                });
            });

    }, [name]);

    return animeSearch;
}

useFetchAnimeSearch.propTypes = {
    name: PropTypes.func.isRequired
}