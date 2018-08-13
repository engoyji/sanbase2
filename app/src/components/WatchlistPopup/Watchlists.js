import React from 'react'
import { connect } from 'react-redux'
import cx from 'classnames'
import {
  createSkeletonProvider,
  createSkeletonElement
} from '@trainline/react-skeletor'
import { Link } from 'react-router-dom'
import { compose } from 'recompose'
import { Label, Icon, Popup } from 'semantic-ui-react'
import CreateWatchlistBtn from './CreateWatchlistBtn'
import * as actions from './../../actions/types'
import './Watchlists.css'

const DIV = createSkeletonElement('div', 'pending-header pending-div')

// id is a number of current date for new list,
// until backend will have returned a real id
const isNewestList = id => typeof id === 'number'

export const hasAssetById = ({ id, listItems }) => {
  return listItems.some(item => item.project.id === id)
}

class Watchlists extends React.Component {
  render () {
    const {
      lists = [],
      isNavigation = false,
      isLoading,
      projectId,
      slug,
      watchlistUi,
      createWatchlist,
      removeAssetList
    } = this.props
    return (
      <div className='watchlists'>
        <div className='watchlists__list'>
          {lists.length > 0 ? (
            lists.map(({ id, name, listItems = [] }) => (
              <div key={id} className='watchlists__item'>
                <Link
                  className='watchlists__item__link'
                  to={`/assets/list?name=${name}@${id}`}
                >
                  <DIV className='watchlists__item__name'>
                    <div>{name}</div>
                  </DIV>
                  {!isLoading && (
                    <div className='watchlists__item__description'>
                      <Label>
                        {listItems.length > 0 ? listItems.length : 'empty'}
                      </Label>
                      {isNewestList(id) && (
                        <Label color='green' horizontal>
                          NEW
                        </Label>
                      )}
                    </div>
                  )}
                </Link>
                <div className='watchlists__tools'>
                  {!isNavigation && (
                    <Popup
                      inverted
                      trigger={
                        <Icon
                          size='big'
                          className={cx({
                            'icon-green': hasAssetById({
                              listItems,
                              id: projectId
                            })
                          })}
                          onClick={this.props.toggleAssetInList.bind(this, {
                            projectId,
                            assetsListId: id,
                            slug,
                            listItems
                          })}
                          name={
                            hasAssetById({
                              listItems,
                              id: projectId
                            })
                              ? 'check circle outline'
                              : 'add'
                          }
                        />
                      }
                      content={
                        hasAssetById({
                          listItems,
                          id: projectId
                        })
                          ? 'remove from list'
                          : 'add to list'
                      }
                      position='right center'
                      size='mini'
                    />
                  )}
                  {!isNewestList(id) && (
                    <Popup
                      inverted
                      trigger={
                        <Icon
                          size='big'
                          className='watchlists__tools__move-to-trash'
                          onClick={removeAssetList.bind(this, id)}
                          name='trash'
                        />
                      }
                      content='remove this list'
                      position='right center'
                      size='mini'
                    />
                  )}
                </div>
              </div>
            ))
          ) : (
            <div className='watchlists__empty-list-msg'>
              You don't have any watchlists yet.
            </div>
          )}
        </div>
        <CreateWatchlistBtn
          watchlistUi={watchlistUi}
          createWatchlist={createWatchlist}
        />
      </div>
    )
  }
}

const mapStateToProps = state => {
  return {
    watchlistUi: state.watchlistUi
  }
}

const mapDispatchToProps = (dispatch, ownProps) => ({
  toggleAssetInList: ({ projectId, assetsListId, listItems, slug }) => {
    if (!projectId) return
    const isAssetInList = hasAssetById({
      listItems: ownProps.lists.find(list => list.id === assetsListId)
        .listItems,
      id: projectId
    })
    if (isAssetInList) {
      return dispatch({
        type: actions.USER_REMOVE_ASSET_FROM_LIST,
        payload: { projectId, assetsListId, listItems, slug }
      })
    } else {
      return dispatch({
        type: actions.USER_ADD_ASSET_TO_LIST,
        payload: { projectId, assetsListId, listItems, slug }
      })
    }
  },
  createWatchlist: payload =>
    dispatch({
      type: actions.USER_ADD_NEW_ASSET_LIST,
      payload
    }),
  removeAssetList: id =>
    dispatch({
      type: actions.USER_REMOVE_ASSET_LIST,
      payload: { id }
    })
})

export default compose(
  createSkeletonProvider(
    {
      lists: [
        {
          id: 1,
          name: '******',
          listItems: []
        },
        {
          id: 2,
          name: '******',
          listItems: []
        }
      ]
    },
    ({ isLoading }) => isLoading,
    () => ({
      backgroundColor: '#bdc3c7',
      color: '#bdc3c7'
    })
  ),
  connect(mapStateToProps, mapDispatchToProps)
)(Watchlists)
