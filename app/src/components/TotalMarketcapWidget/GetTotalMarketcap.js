import React from 'react'
import { graphql, compose } from 'react-apollo'
import { connect } from 'react-redux'
import {
  totalMarketcapGQL,
  constructTotalMarketcapGQL,
  projectsListHistoryStatsGQL
} from './TotalMarketcapGQL'
import TotalMarketcapWidget from './TotalMarketcapWidget'
import moment from 'moment'

const composeHistoryPriceProps = slug => ({
  data: { historyPrice = [] },
  ownProps: { historyPrices: ownHistoryPrices = {} }
}) => ({
  historyPrices: {
    ...ownHistoryPrices,
    [slug]: historyPrice[slug]
  }
})

const getMarketcapQuery = (type, projects) => {
  const from = moment()
    .subtract(3, 'months')
    .utc()
    .format()

  if (type !== 'list') {
    return graphql(totalMarketcapGQL, {
      props: ({ data: { historyPrice = [] } }) => ({
        historyPrices: {
          TOTAL_MARKET: historyPrice
        }
      }),
      options: () => ({
        variables: {
          from,
          slug: 'TOTAL_MARKET'
        }
      })
    })
  }

  // const slugs = projects.slice(0, 10).map(({ slug }) => slug)
  // console.log(projects)
  const slugs = projects
    .slice()
    .sort(
      ({ marketcapUsd: a_marketcapUsd }, { marketcapUsd: b_marketcapUsd }) =>
        a_marketcapUsd < b_marketcapUsd ? 1 : -1
    )
    .map(({ slug }) => slug)

  // console.log(
  //   projects
  //     .slice()
  //     .sort(
  //       ({ marketcapUsd: a_marketcapUsd }, { marketcapUsd: b_marketcapUsd }) =>
  //         (a_marketcapUsd < b_marketcapUsd ? 1 : -1)
  //     )
  //     .slice(0, 3)
  // )
  console.log(slugs, from)

  const slugsQuery = graphql(projectsListHistoryStatsGQL, {
    props: ({ data: { projectsListHistoryStats = [] } }) => ({
      historyPrices: {
        TOTAL_MARKET: projectsListHistoryStats
      }
    }),
    options: () => ({
      variables: {
        from,
        slugs,
        to: moment()
          .utc()
          .format()
      }
    })
  })

  if (projects.length > 1) {
    const top3Slugs = slugs.slice(0, 3)
    const slugsQuery2 = graphql(constructTotalMarketcapGQL(top3Slugs, from), {
      props: ({ data: historyPrice = {}, ownProps: { historyPrices } }) => {
        return top3Slugs.reduce(
          (acc, slug) => {
            acc.historyPrices[slug] = historyPrice['_' + slug.replace(/-/g, '')]
            return acc
          },
          {
            historyPrices,
            loading: historyPrice.loading
          }
        )
      }
    })

    return compose(
      slugsQuery,
      slugsQuery2
    )
  }

  return slugsQuery
}

const GetTotalMarketcap = ({ type, from, projects, ...rest }) => {
  const resultQuery = getMarketcapQuery(type, projects)
  const HistoryQuery = resultQuery(TotalMarketcapWidget)
  return <HistoryQuery />
}

const mapStateToProps = state => ({
  projects: state.projects.items
})

export default connect(mapStateToProps)(GetTotalMarketcap)
