import { useEffect, useState } from "react";
import { getRecomendations } from "../helpers/getRecomendations";

export const useFetchRecomendations = () => {
    const [state, setState] = useState({
        data: [],
        loading: true
    });

    useEffect(() => {
        getRecomendations()
            .then(imgs => {
                setState({
                    data: imgs,
                    loading: false
                });

            });


    }, []);

    return state;


}