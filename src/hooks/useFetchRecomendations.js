import { useEffect, useState } from "react";
import { useRecomendations } from "./useRecomendations";


export const useFetchRecomendations = () => {
    const result = useRecomendations();
    console.log(result)

    const [state, setState] = useState({
        data: [],
        loading: false
    });

    useEffect(() => {
            setState({
                data: result,
                loading: true
            });
    }, [result.length>1]);

    return state;


}