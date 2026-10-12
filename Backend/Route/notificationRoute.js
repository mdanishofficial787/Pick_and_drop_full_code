const express = require('express');
const router = express.Router();
const Notification = require('../schema/Notification');

router.get('/', async (req, res) => {
  try {
    const { customerId, driverId, type } = req.query;
    let query = {};
    if (type) query.type = type;
    
    let userConds = [];
    if (customerId) userConds.push({ customerId });
    if (driverId) userConds.push({ driverId });
    
    if (userConds.length > 0) {
      query.$or = userConds;
    }
    
    const notifications = await Notification.find(query).sort({ createdAt: -1 });
    res.json({ success: true, notifications });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
