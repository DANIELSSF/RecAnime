import React from 'react'

export const RecomendationsItem = ({ id1, id2, title1, title2, url1, url2 }) => {

    return (
        <>
            <div className='card'>
                <img src={url1} alt={title1}></img>
                <p>{title1}</p>
                <img src={url2} alt={title2}></img>
                <p>{title2}</p>
            </div>
        </>
    );
}
