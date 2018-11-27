import React from 'react'
import { graphql } from 'react-apollo'
import Slider from 'react-slick'
import Widget from '../Widget/Widget'
import LatestWatchlistsWidgetItem from './LatestWatchlistsWidgetItem'
import { latestWatchlistsGQL } from './latestWatchlistsGQL'
import { sliderSettings } from '../InsightsWidget/InsightsWidget'
import styles from './LatestWatchlists.module.css'

const MAX_WATCHLISTS_COUNT = 5

const LatestWatchlistsWidget = ({ data: { fetchAllPublicUserLists = [] } }) => {
  return (
    <Widget className={styles.widget} title={'Latest Watchlists'}>
      <Slider {...sliderSettings}>
        {fetchAllPublicUserLists
          .slice(0, MAX_WATCHLISTS_COUNT)
          .map(({ id, name, listItems = [], insertedAt, user = {} }) => (
            <LatestWatchlistsWidgetItem
              key={id}
              id={id}
              name={name}
              listItems={listItems}
              createdAt={insertedAt}
              user={user}
            />
          ))}
      </Slider>
    </Widget>
  )
}

export default graphql(latestWatchlistsGQL)(LatestWatchlistsWidget)