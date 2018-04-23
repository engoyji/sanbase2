import React, { Fragment } from 'react'
import debounce from 'lodash.debounce'
import { Helmet } from 'react-helmet'
import Raven from 'raven-js'
import {
  compose,
  withState,
  pure
} from 'recompose'
import { connect } from 'react-redux'
import { Button, Header, Icon, Modal, Message } from 'semantic-ui-react'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import { NavLink } from 'react-router-dom'
import Panel from './../components/Panel'
import PostList from './../components/PostList'
import { simpleSort } from './../utils/sortMethods'
import ModalConfirmDeletePost from './Insights/ConfirmDeletePostModal'
import { allInsightsPublicGQL, allInsightsGQL } from './Insights/currentPollGQL'
import './EventVotes.css'

const POLLING_INTERVAL = 10000

const voteMutationHelper = ({postId, action = 'vote'}) => ({
  variables: {postId: parseInt(postId, 10)},
  optimisticResponse: {
    __typename: 'Mutation',
    [action]: {
      __typename: 'Post',
      id: postId
    }
  },
  update: (proxy, { data: { vote, unvote } }) => {
    const changedPost = action === 'vote' ? vote : unvote
    const data = proxy.readQuery({ query: allInsightsPublicGQL })
    const newPosts = [...data.allInsights]
    const postIndex = newPosts.findIndex(post => post.id === changedPost.id)
    newPosts[postIndex].votedAt = action === 'vote' ? new Date() : null
    data.allInsights = newPosts
    proxy.writeQuery({ query: allInsightsPublicGQL, data })
  }
})

const getPosts = (match, history, Posts) => {
  const showedMyPosts = match.path.split('/')[2] === 'my' && Posts.hasUserInsights
  const showedUserByIdPosts = match.path.split('/')[2] === 'users'
  if (showedMyPosts) {
    return Posts.userPosts
  }
  if (showedUserByIdPosts) {
    return Posts.postsByUserId
  }
  return Posts.filteredPosts
}

const EventVotes = ({
  Posts = {
    posts: [],
    filteredPosts: [],
    userPosts: [],
    loading: true,
    isEmpty: false,
    hasUserInsights: false,
    isError: false,
    errorMessage: '',
    refetch: null
  },
  votePost,
  unvotePost,
  location,
  history,
  match,
  user,
  toggleLoginRequest,
  isToggledLoginRequest,
  toggleDeletePostRequest,
  isToggledDeletePostRequest,
  setDeletePostId,
  deletePostId = undefined
}) => {
  const showedMyPosts = match.path.split('/')[2] === 'my' && Posts.hasUserInsights

  return ([
    <Fragment key='modal-login-request'>
      {isToggledLoginRequest &&
        <ModalRequestLogin
          toggleLoginRequest={toggleLoginRequest}
          history={history} />}
    </Fragment>,
    <Fragment key='modal-delete-post-request'>
      {isToggledDeletePostRequest &&
        <ModalConfirmDeletePost
          deletePostId={deletePostId}
          toggleForm={() => {
            if (isToggledDeletePostRequest) {
              setDeletePostId(undefined)
            }
            toggleDeletePostRequest(!isToggledDeletePostRequest)
          }} />}
    </Fragment>,
    <div className='page event-votes' key='page-event-votes'>
      <Helmet>
        <title>SANbase: Insights</title>
      </Helmet>
      {location.state && location.state.postCreated &&
        <Message positive>
          <Message.Header>
            <span role='img' aria-label='Clap'>👏</span>
            <span role='img' aria-label='Clap'>👏</span>
            <span role='img' aria-label='Clap'>👏</span>
            Insight was created
          </Message.Header>
          <p>We need some time to approve your insight...</p>
        </Message>}
      <div className='event-votes-rows'>
        <div className='event-votes-navs'>
          {Posts.hasUserInsights &&
            <NavLink
              className='event-votes-navigation__add-link'
              to={'/insights/my'}>
              My Insights
            </NavLink>}
        </div>
        <Panel className='event-votes-content'>
          <div className='panel-header'>
            Insights
          </div>
          <div className='event-votes-control'>
            <div className='event-votes-navigation'>
              <NavLink
                className='event-votes-navigation__link'
                activeClassName='event-votes-navigation__link--active'
                exact
                to={'/insights'}>
                POPULAR
              </NavLink>
              <NavLink
                className='event-votes-navigation__link'
                activeClassName='event-votes-navigation__link--active'
                exact
                to={'/insights/newest'}>
                NEWEST
              </NavLink>
            </div>
            <div>

              {user.token
                ? <NavLink
                  className='event-votes-navigation__add-link'
                  to={'/insights/new'}>
                  Add new insight
                </NavLink>
                : <a
                  onClick={() => toggleLoginRequest(!isToggledLoginRequest)}
                  className='event-votes-navigation__add-link'>
                    Add new insight
                  </a>}
            </div>
          </div>
          {Posts.isEmpty && !showedMyPosts
            ? <Message><h2>We don't have any insights yet.</h2></Message>
            : <PostList {...Posts}
              posts={getPosts(match, history, Posts)}
              userId={showedMyPosts ? user.data.id : undefined}
              toggleLoginRequest={toggleLoginRequest}
              deletePost={postId => {
                setDeletePostId(postId)
                toggleDeletePostRequest(true)
              }}
              votePost={debounce(postId => {
                user.token
                  ? votePost(voteMutationHelper({postId, action: 'vote'}))
                  .then(data => Posts.refetch())
                  .catch(e => Raven.captureException(e))
                  : toggleLoginRequest(!isToggledLoginRequest)
              }, 100)}
              unvotePost={debounce(postId => {
                user.token
                  ? unvotePost(voteMutationHelper({postId, action: 'unvote'}))
                  .then(data => Posts.refetch())
                  .catch(e => Raven.captureException(e))
                  : toggleLoginRequest(!isToggledLoginRequest)
              }, 100)}
          />}
        </Panel>
        <div className='event-votes-sidebar'>
          <Panel>
            <div className='cta-subscription'>
              <span className=''>Get new signals/insights about crypto in your inbox, every day</span>
              <div id='mc_embed_signup'>
                <form action='//santiment.us14.list-manage.com/subscribe/post?u=122a728fd98df22b204fa533c&amp;id=80b55fcb45' method='post' id='mc-embedded-subscribe-form' name='mc-embedded-subscribe-form' className='validate' target='_blank'>
                  <div id='mc_embed_signup_scroll'>
                    <input type='email' defaultValue='' name='EMAIL' className='email' id='mce-EMAIL' placeholder='Your email address' required />
                    <div className='hidden-xs-up' aria-hidden='true'>
                      <input type='text' name='b_122a728fd98df22b204fa533c_80b55fcb45' tabIndex='-1' value='' />
                    </div>
                    <div className='clear'>
                      <input type='submit' value='Subscribe' name='subscribe' id='mc-embedded-subscribe' className='button' />
                    </div>
                  </div>
                </form>
              </div>
            </div>
          </Panel>
        </div>
      </div>
    </div>
  ])
}

const ModalRequestLogin = ({history, toggleLoginRequest}) => (
  <Modal defaultOpen onClose={() => toggleLoginRequest(false)} closeIcon>
    <Header content='Create an account to get your Sanbase experience.' />
    <Modal.Content>
      <p>By having a Sanbase account, you can see more data and insights about crypto projects.
      You can vote and comment on all you favorite insights and more.</p>
    </Modal.Content>
    <Modal.Actions>
      <Button
        onClick={() =>
          history.push(`/login?redirect_to=${history.location.pathname}`)}
        color='green'>
        <Icon name='checkmark' /> Login or Sign up
      </Button>
    </Modal.Actions>
  </Modal>
)

const votePostGQL = gql`
  mutation vote($postId: Int!){
    vote(postId: $postId) {
      id
    }
  }
`

const unvotePostGQL = gql`
  mutation unvote($postId: Int!){
    unvote(postId: $postId) {
      id
    }
  }
`

export const sortByPopular = posts => {
  return posts.sort((postA, postB) =>
    simpleSort(postA.totalSanVotes, postB.totalSanVotes)
  )
}

export const sortByNewest = posts => {
  return posts.sort((postA, postB) =>
    simpleSort(
      new Date(postA.createdAt).getTime(),
      new Date(postB.createdAt).getTime()
    )
  )
}

const mapDataToProps = props => {
  const { Insights, ownProps } = props
  const filter = ownProps.match.path.split('/')[2] || 'popular'
  const posts = Insights.allInsights || []
  let filteredPosts = posts
    // TODO: We should return this filter in the near future
    // .filter(post => post.state === 'approved')
    .map(post => {
      return {
        totalSanVotes: parseFloat(post.totalSanVotes) || 0,
        ...post}
    })
  filteredPosts = sortByNewest(filteredPosts)
  if (filter === 'popular') {
    filteredPosts = sortByPopular(filteredPosts)
  }

  const userPosts = sortByNewest(
    posts.filter(post => post.user.id === ownProps.user.data.id)
  )

  const postsByUserId = filter === 'users'
    ? sortByNewest(
      posts.filter(post => post.user.id === ownProps.match.params.userId)
    )
    : []

  if (Insights.error) {
    throw new Error(Insights.error)
  }

  return {
    Posts: {
      posts,
      filteredPosts,
      userPosts,
      postsByUserId,
      refetch: Insights.refetch,
      loading: Insights.loading,
      isEmpty: Insights.currentPoll &&
        filteredPosts &&
        filteredPosts.length === 0,
      hasUserInsights: userPosts.length > 0,
      isError: !!Insights.error || false,
      errorMessage: Insights.error ? Insights.error.message : ''
    }
  }
}

const mapStateToProps = state => {
  return {
    user: state.user
  }
}

const enhance = compose(
  connect(
    mapStateToProps
  ),
  withState('isToggledLoginRequest', 'toggleLoginRequest', false),
  withState('isToggledDeletePostRequest', 'toggleDeletePostRequest', false),
  withState('deletePostId', 'setDeletePostId', undefined),
  graphql(allInsightsPublicGQL, {
    name: 'Insights',
    props: mapDataToProps,
    options: ({user}) => ({
      skip: !user,
      pollInterval: POLLING_INTERVAL
    })
  }),
  graphql(allInsightsGQL, {
    name: 'Poll',
    props: mapDataToProps,
    options: ({user}) => ({
      skip: user,
      pollInterval: POLLING_INTERVAL
    })
  }),
  graphql(votePostGQL, {
    name: 'votePost'
  }),
  graphql(unvotePostGQL, {
    name: 'unvotePost'
  }),
  pure
)

export default enhance(EventVotes)
