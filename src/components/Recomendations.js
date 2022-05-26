import React from 'react'
import { useFetchRecomendations } from '../hooks/useFetchRecomendations'
import { useRecomendations } from '../hooks/useRecomendations';
import { RecomendationsItem } from './RecomendationsItem';

export const Recomendations = () => {
    const {data,loading} = useFetchRecomendations();
    return (
        <>
            {!loading && <p className='animate__animated animate__zoomIn'>Loading...</p>}
            <div className='card-grid'>
                {
                    data.map(img => (
                        <RecomendationsItem
                            key={img.id}
                            {...img} />
                    ))
                }
            </div>
        </>
    )

}
