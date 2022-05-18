import React from 'react'
import { useFetchRecomendations } from '../hooks/useFetchRecomendations'
import { RecomendationsItem } from './RecomendationsItem';

export const Recomendations = () => {
    const { data: images, loading } = useFetchRecomendations();
    console.log(images)
    return (
        <>
            {loading && <p className='animate__animated animate__zoomIn'>Loading...</p>}
            <div className='card-grid'>
                {
                    images.map(img => (
                        <RecomendationsItem
                            key={img.idkey}
                            {...img} />
                    ))
                }
            </div>
        </>
    )

}
