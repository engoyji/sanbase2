import React from 'react'
import {
  Button,
  Popup
} from 'semantic-ui-react'
import Balance from './../components/Balance'
import './AuthControl.css'

const AccountLinks = ({
  logout,
  openSettings,
  username
}) => (
  <div className='acct-links'>
    <ul>
      {username &&
        <li>
          <div className='account-name'>
            <a href='#'>{username}</a>
          </div>
        </li>}
      <li>
        <a href='#' onClick={openSettings}>Settings</a>
      </li>
      <li>
        <a href='#' onClick={logout}>Logout</a>
      </li>
    </ul>
  </div>
)

const AuthControl = ({
  user,
  login,
  logout,
  openSettings,
  isDesktop = true
}) => {
  if (user.username && isDesktop) {
    return (
      <div className='user-auth-control'>
        <Popup wide trigger={
          <div className='acct'>
            <Balance user={user} />
            <i className='fa fa-caret-down' />
          </div>
        } on='click'>
          <AccountLinks
            username={user.username}
            openSettings={openSettings}
            logout={logout} />
        </Popup>
      </div>
    )
  }
  if (user.username && !isDesktop) {
    return (
      <div className='user-auth-control'>
        <div className='acct'>
          <Balance user={user} />
        </div>
        <AccountLinks
          openSettings={openSettings}
          logout={logout} />
      </div>
    )
  }
  return (
    <div className='user-auth-control'>
      <Button
        onClick={login}>
        Login
      </Button>
    </div>
  )
}

export default AuthControl
