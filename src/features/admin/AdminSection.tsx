import { useEffect, useState } from 'react'
import { useAuth } from '../auth/AuthProvider'
import { RoleManager } from '../team/RoleManager'
import { AdminScreen } from './AdminScreen'
import { getMyAccess, type Access } from './adminApi'

/**
 * Shows the admin screen only when the server reports admin permissions. A plain member
 * sees nothing and no admin data is requested.
 */
export function AdminSection({ teamId }: { teamId: string }) {
  const { client } = useAuth()
  const [access, setAccess] = useState<Access | null>(null)
  const [aal2, setAal2] = useState(false)

  useEffect(() => {
    let active = true
    void getMyAccess(client, teamId).then(
      (r) => active && r.ok && setAccess(r.access),
    )
    return () => {
      active = false
    }
  }, [client, teamId])

  if (!access || (!access.superadmin && access.permissions.length === 0))
    return null
  const canManageRoles =
    access.superadmin || access.permissions.includes('operational_roles.manage')
  return (
    <>
      <AdminScreen teamId={teamId} access={access} onAssurance={setAal2} />
      {canManageRoles ? <RoleManager teamId={teamId} aal2={aal2} /> : null}
    </>
  )
}
