# scst_ocf_ra
SCST OCF Resource agents for managing ALUA HA targets especially Qlogic fibre channel based

How does it work?

This resource agent currently consists of two parts.

scst_qla2xtgt
scst_aluadg

The scst_qla2xtgt is being used for starting up the Qlogic fibre channel targets in the
cluster nodes.

The initiator group configurations is being stored within the resource agent parameters.
All initiator groups are being created by the resource agent. Afterwards the io grouping
is set up in a way that groups i/o together for all initiators within one initiator group.

So optimally you would put all initiator addresses of ONE system within one initiator group

E.g.

vmware-host1:fcaddra,fcaddrb; vmware-host2:fcaddrc, fcaddrd

This leads to correct i/o grouping per hosts over ALL target ports.

Upon stopping the resource agents destroys the initiator groups and disables the target
ports.

The target ports are being configured within each node's parameters as 'targetports' parameter
there is a small script in usr/local/bin that helps you to find all target port addresses and
setup the node's paramters correctly. Make sure this has been set up correctly before starting
up.

The resource agent will find which target ports belong to the local system and set them up.

==========

After the scst_qla2xtgt is running it is time to create device groups.
A device group is a set of devices that share ALUA state information. Logically it makes sense
to put all devices together in a device group that should always be started or migrated together

e.g. DGA = all devices on your SSD raid array, DGB = all devices on you hard disk raid array or 
similar. Each device group may run on a different node as master.

The scst_dg resource agent creates devices handlers with the configured parameters (virtual name,
filename, ssd or not and so on, please look in the meta data or sample configuration for additional
information).

Afterwards the device is being exported to the specified initiator groups. Special keyword all
exports it to each and every initiator group. Can simplify configuration if you don't need
to setup security barries through initiator groups, e.g. if all initiators that access your
target are trustworthy or in the same category of devices (e.g. vmware host machines).

Please make sure you use one and the same lun number only once or the resource agent will fail
to start up. (e.g. if you use lun0 within DGA and DGB which cannot work as lun0 can be populated
only once. It IS possible to use lun0 with a different device in for initiator group A than for 
initiator group b but I would strongly advice againts this as this complicates configuration.

Finally after the resource agent has been started the device group's target ports are set to
unavailable (remote) and standby (local) ALUA state. As soon as the remote side shows up
the ALUA state is changed to standby/standby. Upon promotion of one agent the ALUA state changes
to active for the promoted node. This iniformation should propagate over all target nodes.

This should generally be possible with n nodes so you could have

active/standby/standby/unavailable e.g. if you have running one master, two slaves and one node
is currently stopped.

It is essential that the targetports node attribute is set up for all nodes you want to run on.
The resource agent determines all remote nodes from this parameters. Nodes that have this
param configured are considered a possible Fibre channel target node and those ports are 
put in the target groups as remote ports.

The n-port capablility is currently not tested because I don't have a capable setup. If this
should be used with DRBD there would ne the necessity for some kind of callback upon promote
and demote action I am currently not aware of how this must be done. If anyone has a hint, get
in contact and I'll consider it.

The result should be one device group with n target port groups, named as the cluster nodes.

Here is a snippet from a sample configuration:

node 1: alpha \
        attributes nodetype=fctarget targetports="21:00:00:24:ff:60:d0:10,21:00:00:24:ff:60:d0:11"
node 2: beta \
        attributes nodetype=fctarget targetports="21:00:00:1b:32:0b:52:75,21:01:00:1b:32:2b:52:75"
primitive scst_qla ocf:onesty:scst_qla2xtgt \
        params initiators="vmwtest=50:01:43:80:03:b0:23:34,50:01:43:80:03:b0:23:36" \
        op start interval=0s timeout=120s \
        op stop interval=0s timeout=360s \
        op monitor interval=120s timeout=20s
primitive scst_dg_dummy ocf:onesty:scst_aluadg \
        params groupname=dummy tgtdriver=qla2x00t reload=0 device0="handler=vdisk_nullio,virtname=lu0dummy,dummy=1,export0=all:0" \
        op start interval=0s timeout=120s \
        op stop interval=0s timeout=240s \
        op demote interval=0s timeout=120s \
        op monitor role=Master interval=120s timeout=30s \
        op monitor role=Slave interval=180s timeout=30s
ms ms_scst_dg_dummy scst_dg_dummy \
        meta interleave=true master-max=1 master-node-max=1 clone-max=2 clone-node-max=1 notify=true target-role=Started

Make sure you have proper location/ colocation and order constraints in place.


=======
How to adjust configuration?

Both resource agents support the reload action which enable pacemaker to reconfigure them
without restarting. Unfortunately it is not possible to reload() a ra automatically
upon reconfiguration of another one. So if you reconfigure the scst_qla2xtgt you need to
manually reload the scst_aluadg resource agents above.

E.g. if you add initiator groups you won't see the devices exported to them afterwards
without reloading the scst_aluadg RA. Therefore the reload dummy parameter exists.

Just change this one (which does nothing) and reload will be triggered. Afterwards the
device exports are being corrected.

=======
What about other target drivers?

Yes, I have considered other target drivers (iscsi, infiniband and so on)
I currently don't need them so the first version comes with fc support only.

The ALUA_DG resource agent IS target AGNOSTIC. So you CAN manually configure
the targets and initiator groups (e.g. with scstadmin) and afterwards start 
the aluadg RA, specifying the correct targetports in the node's params and
the correct tgtdriver.

I will be working on a generic target version (scst_target) instead of the
fibre channel specific one as soon I have time for this.

Please let me know if you want to contribute to this.
=======
Why this all - there are already resource agents for scst?

The existing resource agents either just start and stop scst on a node or 
set the alua states. I wanted a resource agent which is

a) capable of holding all of scst's configuration within the cluster
manager
b) instanciable for multiple device groups so you can run n different
device groups on differen nodes if you like.

With a resource agent that just starts and stops you cannot migrate fibre
channel or other hardware targets cause the initiator does not know to 
which ports it should fail over (different target port addresses) so this
only works for iscsi.

Only setting the ALUA states is better but still needs to have the configuration
synced between the nodes, if you forget to sync you lose devices after failover.
I wanted to rule out as much as possible operator errors.

Finally if you can run n instances of the RA it helps you e.g. spreading
load over your targets, which may be helpful for some of you.