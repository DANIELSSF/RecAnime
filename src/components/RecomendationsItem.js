import React from 'react'

export const RecomendationsItem = ( {images,title} ) => {
    
    return (
        <>
            <div className='card'>
                <img src={images} alt={title}></img>
                <p><strong>{title}</strong></p>
            </div>
        </>
    );
}
